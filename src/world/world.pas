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
  TILE_VOX = 4;              { voxels per tile edge }
  VOX      = 0.25;           { world units per voxel }
  TILE     = TILE_VOX * VOX; { world units per tile = 1.0 }
  FLOOR_TOP_Y = VOX;         { top of the floor voxel layer }

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
    slotKey: array of Int64;
    slotChunk: array of PChunk;
    slotState: array of Byte;   { 0 empty, 1 used, 2 dead (tombstone) }
    cap, live, filled: LongInt;
    palette: array[0..254] of TVoxRGBA;
    tw: PTileWorld;
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
  w.cap := cap; w.live := 0; w.filled := 0;
  SetLength(w.slotKey, cap);
  SetLength(w.slotChunk, cap);
  SetLength(w.slotState, cap);
  for i := 0 to cap - 1 do begin
    w.slotState[i] := 0;
    w.slotChunk[i] := nil;
  end;
end;

function HashIndex(const w: TWorld; key: Int64): LongInt;
begin
  HashIndex := LongInt((QWord(key) * QWord($9E3779B97F4A7C15)) shr 40) and (w.cap - 1);
end;

function HashLookup(const w: TWorld; key: Int64): PChunk;
var
  idx: LongInt;
begin
  idx := HashIndex(w, key);
  while w.slotState[idx] <> 0 do begin
    if (w.slotState[idx] = 1) and (w.slotKey[idx] = key) then begin
      HashLookup := w.slotChunk[idx];
      exit;
    end;
    idx := (idx + 1) and (w.cap - 1);
  end;
  HashLookup := nil;
end;

procedure HashGrow(var w: TWorld); forward;

procedure HashInsert(var w: TWorld; key: Int64; c: PChunk);
var
  idx, dead: LongInt;
begin
  if (w.filled + 1) * 10 > w.cap * 7 then HashGrow(w);
  idx := HashIndex(w, key);
  dead := -1;
  while w.slotState[idx] <> 0 do begin
    if (w.slotState[idx] = 2) and (dead < 0) then dead := idx
    else if (w.slotState[idx] = 1) and (w.slotKey[idx] = key) then begin
      w.slotChunk[idx] := c;
      exit;
    end;
    idx := (idx + 1) and (w.cap - 1);
  end;
  if dead >= 0 then idx := dead
  else Inc(w.filled);
  w.slotKey[idx] := key;
  w.slotChunk[idx] := c;
  w.slotState[idx] := 1;
  Inc(w.live);
end;

procedure HashGrow(var w: TWorld);
var
  oldKey: array of Int64;
  oldChunk: array of PChunk;
  oldState: array of Byte;
  i: LongInt;
begin
  oldKey := w.slotKey; oldChunk := w.slotChunk; oldState := w.slotState;
  HashInit(w, w.cap * 2);
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
  if c^.cy <> 0 then exit;   { the dungeon is one chunk tall for now }
  for lz := 0 to CHUNK - 1 do
    for lx := 0 to CHUNK - 1 do begin
      wx := c^.cx * CHUNK + lx;
      wz := c^.cz * CHUNK + lz;
      tx := FloorDiv(wx, TILE_VOX);
      ty := FloorDiv(wz, TILE_VOX);
      stx := wx - tx * TILE_VOX;    { 0..TILE_VOX-1 within the tile }
      stz := wz - ty * TILE_VOX;
      t := TileAt(w.tw^, tx, ty);
      th := TileWorldThemeAt(w.tw^, tx, ty);   { the tile's zone theme }
      wall := ThemeTable[th].wallHeight;
      case t of
        TILE_FLOOR:
          ChunkSet(c^, lx, 0, lz, ColIdx(th, COL_FLOOR));
        TILE_WALL:
          for ly := 0 to wall - 1 do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_WALL));
        TILE_DOOR:
          begin
            ChunkSet(c^, lx, 0, lz, ColIdx(th, COL_DOOR));
            { Jamb posts on the edges that face a wall tile. }
            if ((stx = 0) and (TileAt(w.tw^, tx - 1, ty) = TILE_WALL)) or
               ((stx = TILE_VOX - 1) and (TileAt(w.tw^, tx + 1, ty) = TILE_WALL)) or
               ((stz = 0) and (TileAt(w.tw^, tx, ty - 1) = TILE_WALL)) or
               ((stz = TILE_VOX - 1) and (TileAt(w.tw^, tx, ty + 1) = TILE_WALL)) then
              for ly := 1 to wall - 1 do ChunkSet(c^, lx, ly, lz, ColIdx(th, COL_DOOR));
          end;
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
  ChunkInit(c^, cx, cy, cz, w.palette);
  FillChunkFromTiles(w, c);
  ChunkRemesh(c^, VOX);
  HashInsert(w, Pack(cx, cy, cz), c);
end;

{ ---- public ---- }

procedure SetPal(var w: TWorld; slot: LongInt; const col: TThemeColor);
begin
  w.palette[slot].r := col.r; w.palette[slot].g := col.g;
  w.palette[slot].b := col.b; w.palette[slot].a := 255;
end;

procedure WorldInit(out w: TWorld);
var
  t: LongInt;
begin
  FillChar(w, SizeOf(w), 0);
  HashInit(w, 128);
  w.tw := nil;
  { Lay out every theme's tile-kit colours in its own palette block. These are flat
    placeholder colours generated in code, replaced by authored voxel tiles later. }
  FillChar(w.palette, SizeOf(w.palette), 0);
  for t := 0 to NUM_THEMES - 1 do begin
    SetPal(w, t * COLS_PER_THEME + COL_FLOOR, ThemeTable[t].floor);
    SetPal(w, t * COLS_PER_THEME + COL_WALL, ThemeTable[t].wall);
    SetPal(w, t * COLS_PER_THEME + COL_DOOR, ThemeTable[t].door);
    SetPal(w, t * COLS_PER_THEME + COL_STAIR_UP, ThemeTable[t].stairUp);
    SetPal(w, t * COLS_PER_THEME + COL_STAIR_DN, ThemeTable[t].stairDn);
  end;
end;

procedure WorldSetSources(var w: TWorld; tw: PTileWorld);
begin
  w.tw := tw;
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
  for i := 0 to w.cap - 1 do
    if w.slotState[i] = 1 then begin
      cx := w.slotChunk[i]^.cx; cz := w.slotChunk[i]^.cz;
      if (abs(cx - pcx) > KEEP_RADIUS) or (abs(cz - pcz) > KEEP_RADIUS) then begin
        ChunkFree(w.slotChunk[i]^);
        Dispose(w.slotChunk[i]);
        w.slotChunk[i] := nil;
        w.slotState[i] := 2;
        Dec(w.live);
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
  for i := 0 to w.cap - 1 do
    if w.slotState[i] = 1 then begin
      c := w.slotChunk[i];
      if not c^.hasMesh then continue;
      if not FrustumTestAABB(f, c^.mn, c^.mx) then continue;
      model := Mat4Multiply(
        Mat4Translate(c^.cx * base, c^.cy * base, c^.cz * base),
        Mat4Scale(VOX));
      MeshShaderModel(shader, model);
      MeshDraw(c^.gpu);
      Inc(drawn);
    end;
  WorldRender := drawn;
end;

function WorldResidentCount(const w: TWorld): LongInt;
begin
  WorldResidentCount := w.live;
end;

function WorldHasChunk(const w: TWorld; cx, cy, cz: LongInt): Boolean;
begin
  WorldHasChunk := HashLookup(w, Pack(cx, cy, cz)) <> nil;
end;

procedure WorldFree(var w: TWorld);
var
  i: LongInt;
begin
  for i := 0 to w.cap - 1 do
    if w.slotState[i] = 1 then begin
      ChunkFree(w.slotChunk[i]^);
      Dispose(w.slotChunk[i]);
      w.slotChunk[i] := nil;
      w.slotState[i] := 2;
    end;
  w.live := 0;
end;

end.
