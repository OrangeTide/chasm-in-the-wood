unit world;

{** The streaming voxel world.

  Chunks live in a hash map keyed by global chunk coordinate, so the space is
  unbounded and coordinates may be negative. Only a window around the player is
  resident: WorldStream loads chunks within a radius and frees chunks past a larger
  keep radius, so an infinite world costs only its local neighbourhood.

  Tiles come from the streaming tile world (see tileworld), which generates regions
  on demand. Reading a chunk's tiles pulls the regions it overlaps into existence, so
  the voxel window and the generated tile regions advance together as the player
  moves. The scale constants (one tile is TILE_VOX voxels, each VOX world units) are
  the Single place the logical grid and the voxel geometry meet. }

{$mode objfpc}{$H+}

interface

uses
  vecmath, voxfile, voxchunk, tilemap, tileworld, themes, frustum, gpumesh,
  meshbackend, meshshader;

const
  TILE_VOX = 50;             { voxels per tile edge: the authored tiles' footprint }
  VOX      = 0.02;           { world units per voxel }
  TILE     = TILE_VOX * VOX; { world units per tile = 1.0 }
  FLOOR_TOP_Y = TILE;        { top of a floor tile: the authored block is a tile tall }

  { Each theme owns a block of palette entries, one per tile kind. The colour index
    for theme t is t*COLS_PER_THEME + kind + 1 (palette slots are 1-based). }
  COLS_PER_THEME = 5;
  COL_FLOOR    = 0;
  COL_WALL     = 1;
  COL_DOOR     = 2;
  COL_STAIR_UP = 3;
  COL_STAIR_DN = 4;

  LOAD_RADIUS = 6;           { chunks loaded around the player }
  KEEP_RADIUS = 9;           { chunks kept before eviction (hysteresis) }

type
  PChunk = ^TChunk;
  PTileWorld = ^TTileWorld;

  TWorld = record
    SlotKey: array of Int64;
    SlotChunk: array of PChunk;
    SlotState: array of Byte;   { 0 empty, 1 used, 2 dead (tombstone) }
    Cap, Live, Filled: LongInt;
    Palette: array[0..254] of TVoxRGBA;
    Tw: PTileWorld;
  end;

procedure WorldInit(out w: TWorld);
procedure WorldSetSources(var w: TWorld; tw: PTileWorld);
procedure WorldStream(var w: TWorld; ptx, pty: LongInt);
function WorldRender(const w: TWorld; const shader: TMeshShader;
  const clip: TMat4): LongInt;
function WorldResidentCount(const w: TWorld): LongInt;
function WorldHasChunk(const w: TWorld; cx, cy, cz: LongInt): Boolean;
procedure WorldFree(var w: TWorld);

implementation

function FloorDiv(a, b: LongInt): LongInt;
begin
  if a >= 0 then FloorDiv := a div b
  else FloorDiv := -(((-a) + b - 1) div b);
end;

function Pack(cx, cy, cz: LongInt): Int64;
begin
  Pack := (Int64(cx and $1FFFFF) shl 42) or
          (Int64(cy and $1FFFFF) shl 21) or
           Int64(cz and $1FFFFF);
end;

{ ---- hash table with tombstones ---- }

procedure HashInit(var w: TWorld; cap: LongInt);
var
  i: LongInt;
begin
  w.Cap := cap; w.Live := 0; w.Filled := 0;
  SetLength(w.SlotKey, cap);
  SetLength(w.SlotChunk, cap);
  SetLength(w.SlotState, cap);
  for i := 0 to cap - 1 do begin
    w.SlotState[i] := 0;
    w.SlotChunk[i] := nil;
  end;
end;

function HashIndex(const w: TWorld; key: Int64): LongInt;
begin
  { Fibonacci hashing: the multiply wraps mod 2^64 by design, so overflow and range
    checking are off here. }
  {$push}{$Q-}{$R-}
  HashIndex := LongInt((QWord(key) * QWord($9E3779B97F4A7C15)) shr 40) and (w.Cap - 1);
  {$pop}
end;

function HashLookup(const w: TWorld; key: Int64): PChunk;
var
  idx: LongInt;
begin
  idx := HashIndex(w, key);
  while w.SlotState[idx] <> 0 do begin
    if (w.SlotState[idx] = 1) and (w.SlotKey[idx] = key) then begin
      HashLookup := w.SlotChunk[idx];
      exit;
    end;
    idx := (idx + 1) and (w.Cap - 1);
  end;
  HashLookup := nil;
end;

procedure HashGrow(var w: TWorld); forward;

procedure HashInsert(var w: TWorld; key: Int64; c: PChunk);
var
  idx, dead: LongInt;
begin
  if (w.Filled + 1) * 10 > w.Cap * 7 then HashGrow(w);
  idx := HashIndex(w, key);
  dead := -1;
  while w.SlotState[idx] <> 0 do begin
    if (w.SlotState[idx] = 2) and (dead < 0) then dead := idx
    else if (w.SlotState[idx] = 1) and (w.SlotKey[idx] = key) then begin
      w.SlotChunk[idx] := c;
      exit;
    end;
    idx := (idx + 1) and (w.Cap - 1);
  end;
  if dead >= 0 then idx := dead
  else Inc(w.Filled);
  w.SlotKey[idx] := key;
  w.SlotChunk[idx] := c;
  w.SlotState[idx] := 1;
  Inc(w.Live);
end;

procedure HashGrow(var w: TWorld);
var
  oldKey: array of Int64;
  oldChunk: array of PChunk;
  oldState: array of Byte;
  i: LongInt;
begin
  oldKey := w.SlotKey; oldChunk := w.SlotChunk; oldState := w.SlotState;
  HashInit(w, w.Cap * 2);
  for i := 0 to length(oldState) - 1 do
    if oldState[i] = 1 then HashInsert(w, oldKey[i], oldChunk[i]);
end;

{ ---- chunk construction ---- }

function ColIdx(theme, kind: LongInt): Byte;
{ The 1-based palette slot for a tile kind under a theme. }
begin
  ColIdx := theme * COLS_PER_THEME + kind + 1;
end;

procedure FillChunkFromTiles(var w: TWorld; c: PChunk);
var
  lx, ly, lz, wx, wz, tx, ty, stx, stz, h, th, wall: LongInt;
  t: Byte;
begin
  if c^.Cy <> 0 then exit;   { the dungeon is one chunk tall for now }
  for lz := 0 to CHUNK - 1 do
    for lx := 0 to CHUNK - 1 do begin
      wx := c^.Cx * CHUNK + lx;
      wz := c^.Cz * CHUNK + lz;
      tx := FloorDiv(wx, TILE_VOX);
      ty := FloorDiv(wz, TILE_VOX);
      stx := wx - tx * TILE_VOX;    { 0..TILE_VOX-1 within the tile }
      stz := wz - ty * TILE_VOX;
      t := TileAt(w.Tw^, tx, ty);
      th := TileWorldThemeAt(w.Tw^, tx, ty);   { the tile's zone theme }
      wall := ThemeTable[th].WallHeight;
      case t of
        TILE_FLOOR:
          ChunkSet(c^, lx, 0, lz, ColIdx(th, COL_FLOOR));
        TILE_WALL:
          for ly := 0 to wall - 1 do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_WALL));
        TILE_DOOR:
          begin
            ChunkSet(c^, lx, 0, lz, ColIdx(th, COL_DOOR));
            { Jamb posts on the edges that face a wall tile. }
            if ((stx = 0) and (TileAt(w.Tw^, tx - 1, ty) = TILE_WALL)) or
               ((stx = TILE_VOX - 1) and (TileAt(w.Tw^, tx + 1, ty) = TILE_WALL)) or
               ((stz = 0) and (TileAt(w.Tw^, tx, ty - 1) = TILE_WALL)) or
               ((stz = TILE_VOX - 1) and (TileAt(w.Tw^, tx, ty + 1) = TILE_WALL)) then
              for ly := 1 to wall - 1 do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_DOOR));
          end;
        TILE_DOOR_LOCKED:
          { A shut door: a solid leaf filling the opening to wall height. }
          for ly := 0 to wall - 1 do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_DOOR));
        TILE_STAIRS_UP:
          begin
            h := stx;                    { steps rising along the tile }
            for ly := 0 to h do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_STAIR_UP));
          end;
        TILE_STAIRS_DOWN:
          begin
            h := TILE_VOX - 1 - stx;     { steps falling along the tile }
            for ly := 0 to h do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_STAIR_DN));
          end;
      end;
    end;
end;

procedure EnsureChunk(var w: TWorld; cx, cy, cz: LongInt);
var
  c: PChunk;
begin
  if HashLookup(w, Pack(cx, cy, cz)) <> nil then exit;
  New(c);
  ChunkInit(c^, cx, cy, cz, w.Palette);
  FillChunkFromTiles(w, c);
  ChunkRemesh(c^, VOX);
  HashInsert(w, Pack(cx, cy, cz), c);
end;

{ ---- public ---- }

procedure SetPal(var w: TWorld; slot: LongInt; const col: TThemeColor);
begin
  w.Palette[slot].R := col.R; w.Palette[slot].G := col.G;
  w.Palette[slot].B := col.B; w.Palette[slot].A := 255;
end;

procedure WorldInit(out w: TWorld);
var
  t: LongInt;
begin
  FillChar(w, SizeOf(w), 0);
  HashInit(w, 128);
  w.Tw := nil;
  { Lay out every theme's tile-kit colours in its own palette block. These are flat
    placeholder colours generated in code, replaced by authored voxel tiles later. }
  FillChar(w.Palette, SizeOf(w.Palette), 0);
  for t := 0 to NUM_THEMES - 1 do begin
    SetPal(w, t * COLS_PER_THEME + COL_FLOOR, ThemeTable[t].Floor);
    SetPal(w, t * COLS_PER_THEME + COL_WALL, ThemeTable[t].Wall);
    SetPal(w, t * COLS_PER_THEME + COL_DOOR, ThemeTable[t].Door);
    SetPal(w, t * COLS_PER_THEME + COL_STAIR_UP, ThemeTable[t].StairUp);
    SetPal(w, t * COLS_PER_THEME + COL_STAIR_DN, ThemeTable[t].StairDn);
  end;
end;

procedure WorldSetSources(var w: TWorld; tw: PTileWorld);
begin
  w.Tw := tw;
end;

procedure WorldStream(var w: TWorld; ptx, pty: LongInt);
var
  pcx, pcz, cx, cz, i: LongInt;
begin
  pcx := FloorDiv(ptx * TILE_VOX, CHUNK);
  pcz := FloorDiv(pty * TILE_VOX, CHUNK);

  { Load the radius window. The world is unbounded, so there is no clamp; reading a
    chunk's tiles generates the tile regions it needs. }
  for cz := pcz - LOAD_RADIUS to pcz + LOAD_RADIUS do
    for cx := pcx - LOAD_RADIUS to pcx + LOAD_RADIUS do
      EnsureChunk(w, cx, 0, cz);

  { Evict chunks past the keep radius. }
  for i := 0 to w.Cap - 1 do
    if w.SlotState[i] = 1 then begin
      cx := w.SlotChunk[i]^.Cx; cz := w.SlotChunk[i]^.Cz;
      if (abs(cx - pcx) > KEEP_RADIUS) or (abs(cz - pcz) > KEEP_RADIUS) then begin
        ChunkFree(w.SlotChunk[i]^);
        Dispose(w.SlotChunk[i]);
        w.SlotChunk[i] := nil;
        w.SlotState[i] := 2;
        Dec(w.Live);
      end;
    end;
end;

function WorldRender(const w: TWorld; const shader: TMeshShader;
  const clip: TMat4): LongInt;
var
  f: TFrustum;
  i, drawn: LongInt;
  base: Single;
  model: TMat4;
  c: PChunk;
begin
  FrustumFromClip(clip, f);
  base := CHUNK * VOX;
  drawn := 0;
  for i := 0 to w.Cap - 1 do
    if w.SlotState[i] = 1 then begin
      c := w.SlotChunk[i];
      if not c^.HasMesh then continue;
      if not FrustumTestAABB(f, c^.Mn, c^.Mx) then continue;
      model := Mat4Multiply(
        Mat4Translate(c^.Cx * base, c^.Cy * base, c^.Cz * base),
        Mat4Scale(VOX));
      MeshShaderModel(shader, model);
      MeshDraw(c^.Gpu);
      Inc(drawn);
    end;
  WorldRender := drawn;
end;

function WorldResidentCount(const w: TWorld): LongInt;
begin
  WorldResidentCount := w.Live;
end;

function WorldHasChunk(const w: TWorld; cx, cy, cz: LongInt): Boolean;
begin
  WorldHasChunk := HashLookup(w, Pack(cx, cy, cz)) <> nil;
end;

procedure WorldFree(var w: TWorld);
var
  i: LongInt;
begin
  for i := 0 to w.Cap - 1 do
    if w.SlotState[i] = 1 then begin
      ChunkFree(w.SlotChunk[i]^);
      Dispose(w.SlotChunk[i]);
      w.SlotChunk[i] := nil;
      w.SlotState[i] := 2;
    end;
  w.Live := 0;
end;

end.
