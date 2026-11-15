unit world;

{** The voxel world: chunks in one global coordinate space.

  Chunks live in a hash map keyed by chunk coordinate, so the space is unbounded
  and coordinates may be negative. That is the hook for streaming: later, chunks
  are created and evicted around the player with no other change. For now one
  region is built from a tile map and kept resident.

  This unit rasterizes the logical tile map into chunk voxels, keeps chunk meshes
  current, and draws the frustum-visible chunks. The scale constants (one tile is
  TILE_VOX voxels, each VOX world units) are the single place the logical grid and
  the voxel geometry meet. }

{$mode objfpc}{$H+}

interface

uses
  vecmath, voxfile, voxchunk, tilemap, frustum, gpumesh, meshshader;

const
  TILE_VOX = 4;              { voxels per tile edge }
  WALL_VOX = 6;              { wall height in voxels }
  VOX      = 0.25;           { world units per voxel }
  TILE     = TILE_VOX * VOX; { world units per tile = 1.0 }
  FLOOR_TOP_Y = VOX;         { top of the floor voxel layer }

  PAL_FLOOR = 1;
  PAL_WALL  = 2;

type
  TWorld = record
    chunks: array of TChunk;
    nchunks: longint;
    keys: array of int64;      { hash slots: packed chunk coord }
    vals: array of longint;    { hash slots: chunk index, -1 if empty }
    cap: longint;              { hash capacity, a power of two }
    count: longint;            { occupied hash slots }
    palette: array[0..254] of TVoxRGBA;
  end;

procedure WorldInit(out w: TWorld);
procedure WorldSetVoxel(var w: TWorld; wx, wy, wz: longint; v: byte);
procedure WorldBuildFromTileMap(var w: TWorld; const m: TTileMap);
procedure WorldRemesh(var w: TWorld);
function WorldRender(const w: TWorld; const shader: TMeshShader;
  const clip: TMat4): longint;
procedure WorldFree(var w: TWorld);

implementation

function FloorDiv(a, b: longint): longint;
begin
  if a >= 0 then FloorDiv := a div b
  else FloorDiv := -(((-a) + b - 1) div b);
end;

function Pack(cx, cy, cz: longint): int64;
begin
  Pack := (int64(cx and $1FFFFF) shl 42) or
          (int64(cy and $1FFFFF) shl 21) or
           int64(cz and $1FFFFF);
end;

procedure HashInit(var w: TWorld; cap: longint);
var
  i: longint;
begin
  w.cap := cap;
  w.count := 0;
  SetLength(w.keys, cap);
  SetLength(w.vals, cap);
  for i := 0 to cap - 1 do w.vals[i] := -1;
end;

function SlotFor(const w: TWorld; key: int64): longint;
{ Linear-probe to the slot holding key, or the first free slot. }
var
  idx: longint;
begin
  idx := longint((qword(key) * qword($9E3779B97F4A7C15)) shr 40) and (w.cap - 1);
  while (w.vals[idx] <> -1) and (w.keys[idx] <> key) do
    idx := (idx + 1) and (w.cap - 1);
  SlotFor := idx;
end;

procedure HashGrow(var w: TWorld); forward;

procedure HashPut(var w: TWorld; key: int64; chunkIdx: longint);
var
  slot: longint;
begin
  if (w.count + 1) * 10 > w.cap * 7 then HashGrow(w);
  slot := SlotFor(w, key);
  if w.vals[slot] = -1 then begin
    w.keys[slot] := key;
    Inc(w.count);
  end;
  w.vals[slot] := chunkIdx;
end;

procedure HashGrow(var w: TWorld);
var
  oldKeys: array of int64;
  oldVals: array of longint;
  i: longint;
begin
  oldKeys := w.keys; oldVals := w.vals;
  HashInit(w, w.cap * 2);
  for i := 0 to length(oldVals) - 1 do
    if oldVals[i] <> -1 then HashPut(w, oldKeys[i], oldVals[i]);
end;

function FindChunk(const w: TWorld; cx, cy, cz: longint): longint;
var
  slot: longint;
begin
  slot := SlotFor(w, Pack(cx, cy, cz));
  FindChunk := w.vals[slot];   { -1 when absent }
end;

function GetOrCreateChunk(var w: TWorld; cx, cy, cz: longint): longint;
var
  idx: longint;
begin
  idx := FindChunk(w, cx, cy, cz);
  if idx >= 0 then begin GetOrCreateChunk := idx; exit; end;
  idx := w.nchunks;
  Inc(w.nchunks);
  if w.nchunks > length(w.chunks) then
    SetLength(w.chunks, w.nchunks * 2 + 16);
  ChunkInit(w.chunks[idx], cx, cy, cz, w.palette);
  HashPut(w, Pack(cx, cy, cz), idx);
  GetOrCreateChunk := idx;
end;

procedure WorldInit(out w: TWorld);
begin
  FillChar(w, SizeOf(w), 0);
  SetLength(w.chunks, 0);
  w.nchunks := 0;
  HashInit(w, 64);
  { Placeholder tile-kit colours; replaced by authored voxel tiles later. }
  FillChar(w.palette, SizeOf(w.palette), 0);
  w.palette[PAL_FLOOR - 1].r := 66; w.palette[PAL_FLOOR - 1].g := 62;
  w.palette[PAL_FLOOR - 1].b := 56; w.palette[PAL_FLOOR - 1].a := 255;
  w.palette[PAL_WALL - 1].r := 116; w.palette[PAL_WALL - 1].g := 112;
  w.palette[PAL_WALL - 1].b := 106; w.palette[PAL_WALL - 1].a := 255;
end;

procedure WorldSetVoxel(var w: TWorld; wx, wy, wz: longint; v: byte);
var
  cx, cy, cz, idx: longint;
begin
  cx := FloorDiv(wx, CHUNK);
  cy := FloorDiv(wy, CHUNK);
  cz := FloorDiv(wz, CHUNK);
  idx := GetOrCreateChunk(w, cx, cy, cz);
  ChunkSet(w.chunks[idx], wx - cx * CHUNK, wy - cy * CHUNK, wz - cz * CHUNK, v);
end;

procedure WorldBuildFromTileMap(var w: TWorld; const m: TTileMap);
var
  tx, ty, lx, lz, vy, wx0, wz0: longint;
  t: byte;
begin
  for ty := 0 to m.h - 1 do
    for tx := 0 to m.w - 1 do begin
      t := TileGet(m, tx, ty);
      if t = TILE_ROCK then continue;
      wx0 := tx * TILE_VOX;
      wz0 := ty * TILE_VOX;
      for lz := 0 to TILE_VOX - 1 do
        for lx := 0 to TILE_VOX - 1 do begin
          { Floor layer under everything walkable or solid. }
          WorldSetVoxel(w, wx0 + lx, 0, wz0 + lz, PAL_FLOOR);
          if t = TILE_WALL then
            for vy := 1 to WALL_VOX - 1 do
              WorldSetVoxel(w, wx0 + lx, vy, wz0 + lz, PAL_WALL);
        end;
    end;
end;

procedure WorldRemesh(var w: TWorld);
var
  i: longint;
begin
  for i := 0 to w.nchunks - 1 do
    ChunkRemesh(w.chunks[i], VOX);
end;

function WorldRender(const w: TWorld; const shader: TMeshShader;
  const clip: TMat4): longint;
var
  f: TFrustum;
  i, drawn: longint;
  base: single;
  model: TMat4;
begin
  FrustumFromClip(clip, f);
  base := CHUNK * VOX;
  drawn := 0;
  for i := 0 to w.nchunks - 1 do begin
    if not w.chunks[i].hasMesh then continue;
    if not FrustumTestAABB(f, w.chunks[i].mn, w.chunks[i].mx) then continue;
    model := Mat4Multiply(
      Mat4Translate(w.chunks[i].cx * base, w.chunks[i].cy * base,
                    w.chunks[i].cz * base),
      Mat4Scale(VOX));
    MeshShaderModel(shader, model);
    GpuMeshDraw(w.chunks[i].gpu);
    Inc(drawn);
  end;
  WorldRender := drawn;
end;

procedure WorldFree(var w: TWorld);
var
  i: longint;
begin
  for i := 0 to w.nchunks - 1 do ChunkFree(w.chunks[i]);
  w.nchunks := 0;
end;

end.
