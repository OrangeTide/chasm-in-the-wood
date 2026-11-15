unit tileworld;

{** The unbounded, streaming tile map.

  The world is divided into fixed-size regions of tiles. A region is generated the
  first time a tile inside it is read, from a seed derived from the world seed and
  the region's coordinates, so generation is deterministic and a region regenerates
  identically. This makes the tile map effectively infinite: the player can walk any
  direction and new dungeon appears, with no fixed bounds and no load screens.

  Regions join seamlessly because neighbours agree on where corridors cross the
  shared edge. Each edge between two regions has a canonical identity, and both
  regions derive the same crossing position from it, then carve a corridor out to
  that tile. The two crossings meet at the boundary, so the dungeon is one connected
  space across regions.

  Regions are cheap (a byte per tile) and kept resident once generated; because
  generation is deterministic, evicting and regenerating far regions is safe and is
  a later optimisation. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap, roomgraph, worldgen;

const
  REGION = 48;   { tiles per region edge }

type
  PRegion = ^TRegion;
  TRegion = record
    rx, ry: longint;
    cells: array of byte;
    graph: TRoomGraph;
  end;

  TTileWorld = record
    seed: qword;
    slotKey: array of int64;
    slotReg: array of PRegion;
    slotUsed: array of boolean;
    cap, count: longint;
  end;

procedure TileWorldInit(out tw: TTileWorld; seed: qword);
function TileAt(var tw: TTileWorld; tx, ty: longint): byte;
function TileWorldWalkable(var tw: TTileWorld; tx, ty: longint): boolean;
procedure TileWorldSpawn(var tw: TTileWorld; out sx, sy: longint);
function TileWorldRegionCount(const tw: TTileWorld): longint;
procedure TileWorldFree(var tw: TTileWorld);

implementation

function FloorDiv(a, b: longint): longint;
begin
  if a >= 0 then FloorDiv := a div b
  else FloorDiv := -(((-a) + b - 1) div b);
end;

function Mix(seed: qword; a, b, c: longint): qword;
{ A small FNV-style mix of the seed and three integers. }
var
  h: qword;
begin
  h := seed xor qword($CBF29CE484222325);
  h := (h xor qword(longword(a))) * qword($100000001B3);
  h := (h xor qword(longword(b))) * qword($100000001B3);
  h := (h xor qword(longword(c))) * qword($100000001B3);
  Mix := h;
end;

function EdgePos(seed: qword; a, b, axis: longint): longint;
{ A crossing position along a shared edge, off the corners. Both regions that share
  the edge pass its canonical (a, b, axis), so they agree. }
begin
  EdgePos := longint((Mix(seed, a, b, axis + 1) shr 33) mod qword(REGION - 2)) + 1;
end;

{ ---- region hash (grow-only) ---- }

function PackR(rx, ry: longint): int64;
begin
  PackR := (int64(longword(rx)) shl 32) or int64(longword(ry));
end;

procedure HashInit(var tw: TTileWorld; cap: longint);
var
  i: longint;
begin
  tw.cap := cap; tw.count := 0;
  SetLength(tw.slotKey, cap);
  SetLength(tw.slotReg, cap);
  SetLength(tw.slotUsed, cap);
  for i := 0 to cap - 1 do begin
    tw.slotUsed[i] := false;
    tw.slotReg[i] := nil;
  end;
end;

function HashIndex(const tw: TTileWorld; key: int64): longint;
begin
  HashIndex := longint((qword(key) * qword($9E3779B97F4A7C15)) shr 40) and (tw.cap - 1);
end;

function HashLookup(const tw: TTileWorld; key: int64): PRegion;
var
  idx: longint;
begin
  idx := HashIndex(tw, key);
  while tw.slotUsed[idx] do begin
    if tw.slotKey[idx] = key then begin HashLookup := tw.slotReg[idx]; exit; end;
    idx := (idx + 1) and (tw.cap - 1);
  end;
  HashLookup := nil;
end;

procedure HashGrow(var tw: TTileWorld); forward;

procedure HashInsert(var tw: TTileWorld; key: int64; reg: PRegion);
var
  idx: longint;
begin
  if (tw.count + 1) * 10 > tw.cap * 7 then HashGrow(tw);
  idx := HashIndex(tw, key);
  while tw.slotUsed[idx] do idx := (idx + 1) and (tw.cap - 1);
  tw.slotKey[idx] := key;
  tw.slotReg[idx] := reg;
  tw.slotUsed[idx] := true;
  Inc(tw.count);
end;

procedure HashGrow(var tw: TTileWorld);
var
  oldKey: array of int64;
  oldReg: array of PRegion;
  oldUsed: array of boolean;
  i: longint;
begin
  oldKey := tw.slotKey; oldReg := tw.slotReg; oldUsed := tw.slotUsed;
  HashInit(tw, tw.cap * 2);
  for i := 0 to length(oldUsed) - 1 do
    if oldUsed[i] then HashInsert(tw, oldKey[i], oldReg[i]);
end;

{ ---- region generation ---- }

procedure SetCell(reg: PRegion; x, y: longint; v: byte);
begin
  if (x >= 0) and (y >= 0) and (x < REGION) and (y < REGION) then
    reg^.cells[x + y * REGION] := v;
end;

procedure ConnectEdge(reg: PRegion; px, py: longint);
{ Carve an L-corridor from the nearest room's centre out to the edge tile, so the
  crossing connects to the region's room network. }
var
  i, best, bestD, d, ax, ay, cxc, cyc, x, y: longint;
begin
  if reg^.graph.nrooms = 0 then exit;
  best := 0; bestD := high(longint);
  for i := 0 to reg^.graph.nrooms - 1 do begin
    cxc := RoomCenterX(reg^.graph.rooms[i]);
    cyc := RoomCenterY(reg^.graph.rooms[i]);
    d := abs(cxc - px) + abs(cyc - py);
    if d < bestD then begin bestD := d; best := i; end;
  end;
  ax := RoomCenterX(reg^.graph.rooms[best]);
  ay := RoomCenterY(reg^.graph.rooms[best]);
  if ax <= px then for x := ax to px do SetCell(reg, x, ay, TILE_FLOOR)
  else for x := px to ax do SetCell(reg, x, ay, TILE_FLOOR);
  if ay <= py then for y := ay to py do SetCell(reg, px, y, TILE_FLOOR)
  else for y := py to ay do SetCell(reg, px, y, TILE_FLOOR);
end;

procedure GenerateRegion(const tw: TTileWorld; reg: PRegion);
var
  r: TRng;
  sx, sy: longint;
begin
  SetLength(reg^.cells, REGION * REGION);
  RngSeed(r, Mix(tw.seed, reg^.rx, reg^.ry, 0));
  CarveRooms(reg^.cells, REGION, REGION, r, reg^.graph, sx, sy);
  { Four seam crossings, each at a position both neighbours agree on. }
  ConnectEdge(reg, REGION - 1, EdgePos(tw.seed, reg^.rx, reg^.ry, 0));      { right }
  ConnectEdge(reg, 0, EdgePos(tw.seed, reg^.rx - 1, reg^.ry, 0));           { left }
  ConnectEdge(reg, EdgePos(tw.seed, reg^.rx, reg^.ry, 1), REGION - 1);      { bottom }
  ConnectEdge(reg, EdgePos(tw.seed, reg^.rx, reg^.ry - 1, 1), 0);           { top }
  LayWalls(reg^.cells, REGION, REGION);
end;

function EnsureRegion(var tw: TTileWorld; rx, ry: longint): PRegion;
var
  key: int64;
  reg: PRegion;
begin
  key := PackR(rx, ry);
  reg := HashLookup(tw, key);
  if reg <> nil then begin EnsureRegion := reg; exit; end;
  New(reg);
  reg^.rx := rx; reg^.ry := ry;
  GenerateRegion(tw, reg);
  HashInsert(tw, key, reg);
  EnsureRegion := reg;
end;

{ ---- public ---- }

procedure TileWorldInit(out tw: TTileWorld; seed: qword);
begin
  tw.seed := seed;
  tw.count := 0;
  HashInit(tw, 64);
end;

function TileAt(var tw: TTileWorld; tx, ty: longint): byte;
var
  rx, ry: longint;
  reg: PRegion;
begin
  rx := FloorDiv(tx, REGION);
  ry := FloorDiv(ty, REGION);
  reg := EnsureRegion(tw, rx, ry);
  TileAt := reg^.cells[(tx - rx * REGION) + (ty - ry * REGION) * REGION];
end;

function TileWorldWalkable(var tw: TTileWorld; tx, ty: longint): boolean;
var
  t: byte;
begin
  t := TileAt(tw, tx, ty);
  TileWorldWalkable := (t = TILE_FLOOR) or (t = TILE_DOOR);
end;

procedure TileWorldSpawn(var tw: TTileWorld; out sx, sy: longint);
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, 0, 0);
  if reg^.graph.nrooms > 0 then begin
    sx := RoomCenterX(reg^.graph.rooms[0]);
    sy := RoomCenterY(reg^.graph.rooms[0]);
  end else begin
    sx := REGION div 2; sy := REGION div 2;
  end;
end;

function TileWorldRegionCount(const tw: TTileWorld): longint;
begin
  TileWorldRegionCount := tw.count;
end;

procedure TileWorldFree(var tw: TTileWorld);
var
  i: longint;
begin
  for i := 0 to tw.cap - 1 do
    if tw.slotUsed[i] then begin
      Dispose(tw.slotReg[i]);
      tw.slotReg[i] := nil;
      tw.slotUsed[i] := false;
    end;
  tw.count := 0;
end;

end.
