program t_streaming;

{** Tests chunk streaming with no GL context, via the null mesh backend.

  Walks the player across a large level and checks that chunks load near the
  player, evict when left behind, reload on return, and that the resident set
  stays bounded across repeated trips (no runaway growth or missed eviction). }

{$mode objfpc}{$H+}

uses
  tilemap, roomgraph, worldgen, voxchunk, world, meshbackend;

const
  MW = 128;
  MH = 128;
  TOTAL_CHUNKS = (MW * TILE_VOX div CHUNK) * (MH * TILE_VOX div CHUNK);

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function TileChunk(tile: longint): longint;
begin
  TileChunk := (tile * TILE_VOX) div CHUNK;   { tiles are non-negative here }
end;

var
  m: TTileMap;
  g: TRoomGraph;
  w: TWorld;
  r0, maxRes, trip, tx, ty, scx, scz, ccx, ccz: longint;

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

  GenerateDungeon(m, g, MW, MH, 1337);
  WorldInit(w);
  WorldSetSources(w, @m, @g);

  { Resident set at spawn. }
  WorldStream(w, m.spawnX, m.spawnY);
  r0 := WorldResidentCount(w);
  maxRes := r0;
  Check(r0 > 0, 'nothing resident at spawn');
  Check(r0 < TOTAL_CHUNKS, 'whole map resident at spawn (not streaming)');

  scx := TileChunk(m.spawnX); scz := TileChunk(m.spawnY);
  ccx := TileChunk(MW - 1);   ccz := TileChunk(MH - 1);
  Check(WorldHasChunk(w, scx, 0, scz), 'spawn chunk not resident at spawn');
  Check(not WorldHasChunk(w, ccx, 0, ccz), 'far corner already resident at spawn');

  { Walk to the far corner: spawn evicts, corner loads. }
  tx := m.spawnX; ty := m.spawnY;
  WalkTo(MW - 1, MH - 1);
  Check(WorldHasChunk(w, ccx, 0, ccz), 'corner chunk not resident at corner');
  Check(not WorldHasChunk(w, scx, 0, scz), 'spawn chunk not evicted after leaving');

  { Walk back: corner evicts, spawn reloads. }
  WalkTo(m.spawnX, m.spawnY);
  Check(WorldHasChunk(w, scx, 0, scz), 'spawn chunk not reloaded on return');
  Check(not WorldHasChunk(w, ccx, 0, ccz), 'corner chunk not evicted on return');

  { Several round trips must not grow the resident set without bound. }
  for trip := 1 to 3 do begin
    WalkTo(MW - 1, MH - 1);
    WalkTo(m.spawnX, m.spawnY);
  end;
  Check(maxRes < TOTAL_CHUNKS, 'resident set reached the whole map');
  Check(maxRes < 800, 'resident set grew too large (possible missed eviction)');

  WorldFree(w);
  Check(WorldResidentCount(w) = 0, 'chunks remain resident after WorldFree');

  writeln('  spawn resident ', r0, ', max over walk ', maxRes, ' / ',
          TOTAL_CHUNKS, ' total');
  if fails = 0 then writeln('  ok') else halt(1);
end.
