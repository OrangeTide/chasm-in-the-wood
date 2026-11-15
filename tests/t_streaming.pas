program t_streaming;

{** Tests chunk streaming over the unbounded tile world, with no GL context via the
  null mesh backend.

  Walks the player a long way and checks that chunks load near the player, evict when
  left behind, reload on return, and that the resident set stays bounded over
  repeated trips (no runaway growth or missed eviction). }

{$mode objfpc}{$H+}

uses
  tileworld, voxchunk, world, meshbackend;

const
  FAR = 300;   { tiles to walk out, well past the keep radius }

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function TileChunk(tile: longint): longint;
begin
  if tile >= 0 then TileChunk := (tile * TILE_VOX) div CHUNK
  else TileChunk := -((((-tile) * TILE_VOX) + CHUNK - 1) div CHUNK);
end;

var
  tw: TTileWorld;
  w: TWorld;
  r0, maxRes, trip, tx, ty, sx, sy, scx, scz, fcx, fcz: longint;

procedure WalkTo(destX, destY: longint);
begin
  while (tx <> destX) or (ty <> destY) do begin
    if tx < destX then Inc(tx) else if tx > destX then Dec(tx);
    if ty < destY then Inc(ty) else if ty > destY then Dec(ty);
    WorldStream(w, tx, ty);
    if WorldResidentCount(w) > maxRes then maxRes := WorldResidentCount(w);
  end;
end;

begin
  fails := 0;
  MeshBackendUseNull;

  TileWorldInit(tw, 1337);
  WorldInit(w);
  WorldSetSources(w, @tw);
  TileWorldSpawn(tw, sx, sy);

  WorldStream(w, sx, sy);
  r0 := WorldResidentCount(w);
  maxRes := r0;
  Check(r0 > 0, 'nothing resident at spawn');

  scx := TileChunk(sx); scz := TileChunk(sy);
  Check(WorldHasChunk(w, scx, 0, scz), 'spawn chunk not resident at spawn');

  { Walk far out: spawn evicts, the far area loads. }
  tx := sx; ty := sy;
  WalkTo(sx + FAR, sy + FAR);
  fcx := TileChunk(tx); fcz := TileChunk(ty);
  Check(WorldHasChunk(w, fcx, 0, fcz), 'destination chunk not resident');
  Check(not WorldHasChunk(w, scx, 0, scz), 'spawn chunk not evicted after leaving');

  { Walk back: the far area evicts, spawn reloads. }
  WalkTo(sx, sy);
  Check(WorldHasChunk(w, scx, 0, scz), 'spawn chunk not reloaded on return');
  Check(not WorldHasChunk(w, fcx, 0, fcz), 'far chunk not evicted on return');

  { Repeated trips must not grow the resident set without bound. }
  for trip := 1 to 3 do begin
    WalkTo(sx + FAR, sy + FAR);
    WalkTo(sx, sy);
  end;
  Check(maxRes < 800, 'resident set grew too large (possible missed eviction)');

  WorldFree(w);
  TileWorldFree(tw);
  Check(WorldResidentCount(w) = 0, 'chunks remain resident after WorldFree');

  writeln('  spawn resident ', r0, ', max over walk ', maxRes);
  if fails = 0 then writeln('  ok') else halt(1);
end.
