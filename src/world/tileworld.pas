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

  Only the most recently used regions are kept. When the resident count passes a
  cap, the least recently used region is evicted. Because generation is
  deterministic, walking back regenerates an evicted region identically, so eviction
  is free of visible effect. Nothing outside holds a region pointer across calls, so
  a region can be freed safely. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap, roomgraph, worldgen, themes;

const
  REGION = 48;        { tiles per region edge }
  MAX_REGIONS = 128;  { resident region cap before LRU eviction }

  { The four region edges, and the index each seam crossing connects a room through. }
  EDGE_RIGHT  = 0;
  EDGE_LEFT   = 1;
  EDGE_BOTTOM = 2;
  EDGE_TOP    = 3;

type
  PRegion = ^TRegion;
  TRegion = record
    rx, ry: longint;
    cells: array of byte;
    graph: TRoomGraph;
    lastUsed: int64;   { recency clock value at last access }
    hasUp, hasDown: boolean;        { stairs this region hosts, if any }
    upX, upY, downX, downY: longint;
    edgeRoom: array[0..3] of longint;   { local room each seam crossing reaches }
  end;

  { A room's identity across the whole world: its region plus its local index. }
  TRoomRef = record
    rx, ry, idx: longint;
  end;

  TTileWorld = record
    base: qword;                { the raw world seed, before the depth fold }
    seed: qword;                { effective seed, folded with the depth }
    depth: longint;             { which dungeon level this world is }
    slotKey: array of int64;
    slotReg: array of PRegion;
    slotState: array of byte;   { 0 empty, 1 used, 2 dead (tombstone) }
    cap, live, filled: longint;
    clock: int64;
  end;

procedure TileWorldInit(out tw: TTileWorld; seed: qword; depth: longint);
function TileAt(var tw: TTileWorld; tx, ty: longint): byte;
function TileWorldWalkable(var tw: TTileWorld; tx, ty: longint): boolean;
procedure TileWorldSpawn(var tw: TTileWorld; out sx, sy: longint);
{ The stairs in a given region, if it hosts them. Descending from a region's
  down-stair lands on the same region's up-stair one depth down, and ascending
  reverses it, so the player arrives standing on the matching stair. }
function TileWorldRegionUpStair(var tw: TTileWorld; rx, ry: longint;
  out sx, sy: longint): boolean;
function TileWorldRegionDownStair(var tw: TTileWorld; rx, ry: longint;
  out sx, sy: longint): boolean;
function TileWorldDepth(const tw: TTileWorld): longint;
function TileWorldThemeAt(const tw: TTileWorld; tx, ty: longint): longint;
{ The room containing a tile, as a world-wide reference, or false for a corridor or
  rock. The stitched world graph is reached through this and the neighbours below. }
function TileWorldRoomAt(var tw: TTileWorld; tx, ty: longint;
  out ref: TRoomRef): boolean;
{ The rooms directly linked to a room: its region's own portals, plus the seam
  crossings that join it to the rooms in the neighbouring regions. Fills up to
  Length(refs) entries and sets n. This is where separate regions and zones stitch
  into one connected graph. }
procedure TileWorldRoomNeighbours(var tw: TTileWorld; const ref: TRoomRef;
  var refs: array of TRoomRef; out n: longint);
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

{ ---- region hash with tombstones ---- }

function PackR(rx, ry: longint): int64;
begin
  PackR := (int64(longword(rx)) shl 32) or int64(longword(ry));
end;

procedure HashInit(var tw: TTileWorld; cap: longint);
var
  i: longint;
begin
  tw.cap := cap; tw.live := 0; tw.filled := 0;
  SetLength(tw.slotKey, cap);
  SetLength(tw.slotReg, cap);
  SetLength(tw.slotState, cap);
  for i := 0 to cap - 1 do begin
    tw.slotState[i] := 0;
    tw.slotReg[i] := nil;
  end;
end;

function HashIndex(const tw: TTileWorld; key: int64): longint;
begin
  HashIndex := longint((qword(key) * qword($9E3779B97F4A7C15)) shr 40) and (tw.cap - 1);
end;

function HashSlot(const tw: TTileWorld; key: int64): longint;
{ The used slot holding key, or -1. }
var
  idx: longint;
begin
  idx := HashIndex(tw, key);
  while tw.slotState[idx] <> 0 do begin
    if (tw.slotState[idx] = 1) and (tw.slotKey[idx] = key) then begin
      HashSlot := idx; exit;
    end;
    idx := (idx + 1) and (tw.cap - 1);
  end;
  HashSlot := -1;
end;

procedure HashGrow(var tw: TTileWorld); forward;

procedure HashInsert(var tw: TTileWorld; key: int64; reg: PRegion);
var
  idx, dead: longint;
begin
  if (tw.filled + 1) * 10 > tw.cap * 7 then HashGrow(tw);
  idx := HashIndex(tw, key);
  dead := -1;
  while tw.slotState[idx] <> 0 do begin
    if (tw.slotState[idx] = 2) and (dead < 0) then dead := idx;
    idx := (idx + 1) and (tw.cap - 1);
  end;
  if dead >= 0 then idx := dead
  else Inc(tw.filled);
  tw.slotKey[idx] := key;
  tw.slotReg[idx] := reg;
  tw.slotState[idx] := 1;
  Inc(tw.live);
end;

procedure HashGrow(var tw: TTileWorld);
var
  oldKey: array of int64;
  oldReg: array of PRegion;
  oldState: array of byte;
  i: longint;
begin
  oldKey := tw.slotKey; oldReg := tw.slotReg; oldState := tw.slotState;
  HashInit(tw, tw.cap * 2);
  for i := 0 to length(oldState) - 1 do
    if oldState[i] = 1 then HashInsert(tw, oldKey[i], oldReg[i]);
end;

procedure EvictLRU(var tw: TTileWorld);
{ Free the least recently used region. The just-created region holds the newest
  clock value, so it is never the victim. }
var
  i, victim: longint;
  best: int64;
begin
  victim := -1;
  best := high(int64);
  for i := 0 to tw.cap - 1 do
    if (tw.slotState[i] = 1) and (tw.slotReg[i]^.lastUsed < best) then begin
      best := tw.slotReg[i]^.lastUsed;
      victim := i;
    end;
  if victim < 0 then exit;
  Dispose(tw.slotReg[victim]);
  tw.slotReg[victim] := nil;
  tw.slotState[victim] := 2;
  Dec(tw.live);
end;

{ ---- region generation ---- }

procedure SetCell(reg: PRegion; x, y: longint; v: byte);
begin
  if (x >= 0) and (y >= 0) and (x < REGION) and (y < REGION) then
    reg^.cells[x + y * REGION] := v;
end;

function ConnectEdge(reg: PRegion; px, py: longint): longint;
{ Carve an L-corridor from the nearest room's centre out to the edge tile, so the
  crossing connects to the region's room network. Returns that room's local index, or
  -1 when the region has no rooms, which is what stitches the seam to a neighbour. }
var
  i, best, bestD, d, ax, ay, cxc, cyc, x, y: longint;
begin
  if reg^.graph.nrooms = 0 then begin
    ConnectEdge := -1;
    exit;
  end;
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
  ConnectEdge := best;
end;

function RegionGenParams(const tw: TTileWorld; rx, ry: longint): TGenParams;
{ The carving parameters for a region come from the theme of the zone it sits in. }
var
  th: TTheme;
begin
  th := ThemeTable[ThemeIndex(tw.seed, rx, ry)];
  RegionGenParams.minLeaf := th.minLeaf;
  RegionGenParams.minRoom := th.minRoom;
  RegionGenParams.maxDepth := th.maxDepth;
end;

procedure GenerateRegion(const tw: TTileWorld; reg: PRegion);
var
  r: TRng;
  sx, sy: longint;
begin
  SetLength(reg^.cells, REGION * REGION);
  RngSeed(r, Mix(tw.seed, reg^.rx, reg^.ry, 0));
  CarveRooms(reg^.cells, REGION, REGION, r, reg^.graph, sx, sy,
             RegionGenParams(tw, reg^.rx, reg^.ry));
  { Four seam crossings, each at a position both neighbours agree on. Record which
    room each reaches, so the seam can stitch to the neighbour's matching edge room. }
  reg^.edgeRoom[EDGE_RIGHT] :=
    ConnectEdge(reg, REGION - 1, EdgePos(tw.seed, reg^.rx, reg^.ry, 0));
  reg^.edgeRoom[EDGE_LEFT] :=
    ConnectEdge(reg, 0, EdgePos(tw.seed, reg^.rx - 1, reg^.ry, 0));
  reg^.edgeRoom[EDGE_BOTTOM] :=
    ConnectEdge(reg, EdgePos(tw.seed, reg^.rx, reg^.ry, 1), REGION - 1);
  reg^.edgeRoom[EDGE_TOP] :=
    ConnectEdge(reg, EdgePos(tw.seed, reg^.rx, reg^.ry - 1, 1), 0);
  LayWalls(reg^.cells, REGION, REGION);
  PlaceDoors(reg^.cells, REGION, REGION);
end;

function StairRegion(base: qword; d, rx, ry: longint): boolean;
{ Whether depth d's region (rx, ry) hosts a down-stair. About one region in four,
  plus the origin on every depth so there is always a reachable descent. The result
  depends on the raw seed and the depth, not the folded per-depth seed, so depth d+1
  can compute depth d's answer when it places its matching up-stairs. }
begin
  if (rx = 0) and (ry = 0) then StairRegion := true
  else StairRegion :=
    (Mix(base xor qword($D1B54A32D192ED03), d, rx, ry) shr 33) mod 4 = 0;
end;

procedure PlaceStairs(const tw: TTileWorld; reg: PRegion);
{ Scatter stairs across the world. A region hosts a down-stair when StairRegion says
  so, and an up-stair when the region one depth up hosted a down-stair, which keeps a
  descent and the ascent back lined up. Stairs sit at room centres, so the player
  arrives standing on one. }
var
  r0, rN, lx, ly: longint;
begin
  reg^.hasUp := false;
  reg^.hasDown := false;
  if reg^.graph.nrooms = 0 then exit;
  r0 := 0;
  rN := reg^.graph.nrooms - 1;
  { Carve at the room centre (region-local), and store the stair's global tile. }
  if StairRegion(tw.base, tw.depth, reg^.rx, reg^.ry) then begin
    lx := RoomCenterX(reg^.graph.rooms[rN]);
    ly := RoomCenterY(reg^.graph.rooms[rN]);
    SetCell(reg, lx, ly, TILE_STAIRS_DOWN);
    reg^.downX := reg^.rx * REGION + lx;
    reg^.downY := reg^.ry * REGION + ly;
    reg^.hasDown := true;
  end;
  if (tw.depth > 0) and (rN <> r0) and
     StairRegion(tw.base, tw.depth - 1, reg^.rx, reg^.ry) then begin
    lx := RoomCenterX(reg^.graph.rooms[r0]);
    ly := RoomCenterY(reg^.graph.rooms[r0]);
    SetCell(reg, lx, ly, TILE_STAIRS_UP);
    reg^.upX := reg^.rx * REGION + lx;
    reg^.upY := reg^.ry * REGION + ly;
    reg^.hasUp := true;
  end;
end;

function EnsureRegion(var tw: TTileWorld; rx, ry: longint): PRegion;
var
  slot: longint;
  reg: PRegion;
begin
  Inc(tw.clock);
  slot := HashSlot(tw, PackR(rx, ry));
  if slot >= 0 then begin
    tw.slotReg[slot]^.lastUsed := tw.clock;
    EnsureRegion := tw.slotReg[slot];
    exit;
  end;
  New(reg);
  reg^.rx := rx; reg^.ry := ry;
  reg^.lastUsed := tw.clock;
  GenerateRegion(tw, reg);
  PlaceStairs(tw, reg);
  HashInsert(tw, PackR(rx, ry), reg);
  if tw.live > MAX_REGIONS then EvictLRU(tw);
  EnsureRegion := reg;
end;

{ ---- public ---- }

procedure TileWorldInit(out tw: TTileWorld; seed: qword; depth: longint);
begin
  tw.base := seed;
  tw.depth := depth;
  { Fold the depth into the seed so each depth is a different dungeon. }
  tw.seed := Mix(seed, depth, 0, 0);
  tw.clock := 0;
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
  TileWorldWalkable := (t = TILE_FLOOR) or (t = TILE_DOOR) or
                       (t = TILE_STAIRS_DOWN) or (t = TILE_STAIRS_UP);
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

function TileWorldRegionUpStair(var tw: TTileWorld; rx, ry: longint;
  out sx, sy: longint): boolean;
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, rx, ry);
  sx := reg^.upX; sy := reg^.upY;
  TileWorldRegionUpStair := reg^.hasUp;
end;

function TileWorldRegionDownStair(var tw: TTileWorld; rx, ry: longint;
  out sx, sy: longint): boolean;
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, rx, ry);
  sx := reg^.downX; sy := reg^.downY;
  TileWorldRegionDownStair := reg^.hasDown;
end;

function TileWorldDepth(const tw: TTileWorld): longint;
begin
  TileWorldDepth := tw.depth;
end;

function TileWorldThemeAt(const tw: TTileWorld; tx, ty: longint): longint;
{ The theme index of the tile's region. Pure: it reads no region, so it never
  triggers generation. }
begin
  TileWorldThemeAt := ThemeIndex(tw.seed, FloorDiv(tx, REGION), FloorDiv(ty, REGION));
end;

function TileWorldRoomAt(var tw: TTileWorld; tx, ty: longint;
  out ref: TRoomRef): boolean;
var
  rx, ry, li: longint;
  reg: PRegion;
begin
  rx := FloorDiv(tx, REGION);
  ry := FloorDiv(ty, REGION);
  reg := EnsureRegion(tw, rx, ry);
  li := RoomGraphRoomAt(reg^.graph, tx - rx * REGION, ty - ry * REGION);
  if li < 0 then begin
    TileWorldRoomAt := false;
    exit;
  end;
  ref.rx := rx; ref.ry := ry; ref.idx := li;
  TileWorldRoomAt := true;
end;

procedure TileWorldRoomNeighbours(var tw: TTileWorld; const ref: TRoomRef;
  var refs: array of TRoomRef; out n: longint);
var
  reg, nb: PRegion;
  i, cap: longint;
  edge: array[0..3] of longint;

  procedure Push(rx, ry, idx: longint);
  begin
    if (idx >= 0) and (n < cap) then begin
      refs[n].rx := rx; refs[n].ry := ry; refs[n].idx := idx;
      Inc(n);
    end;
  end;

begin
  n := 0;
  cap := Length(refs);
  reg := EnsureRegion(tw, ref.rx, ref.ry);
  { Portals inside the room's own region. }
  for i := 0 to reg^.graph.nportals - 1 do begin
    if reg^.graph.portals[i].a = ref.idx then
      Push(ref.rx, ref.ry, reg^.graph.portals[i].b)
    else if reg^.graph.portals[i].b = ref.idx then
      Push(ref.rx, ref.ry, reg^.graph.portals[i].a);
  end;
  { Copy the edge rooms before ensuring neighbours, which may move region pointers. }
  for i := 0 to 3 do edge[i] := reg^.edgeRoom[i];
  { Seam crossings: if this room reaches an edge, stitch to the matching edge room of
    the neighbouring region across that seam. }
  if edge[EDGE_RIGHT] = ref.idx then begin
    nb := EnsureRegion(tw, ref.rx + 1, ref.ry);
    Push(ref.rx + 1, ref.ry, nb^.edgeRoom[EDGE_LEFT]);
  end;
  if edge[EDGE_LEFT] = ref.idx then begin
    nb := EnsureRegion(tw, ref.rx - 1, ref.ry);
    Push(ref.rx - 1, ref.ry, nb^.edgeRoom[EDGE_RIGHT]);
  end;
  if edge[EDGE_BOTTOM] = ref.idx then begin
    nb := EnsureRegion(tw, ref.rx, ref.ry + 1);
    Push(ref.rx, ref.ry + 1, nb^.edgeRoom[EDGE_TOP]);
  end;
  if edge[EDGE_TOP] = ref.idx then begin
    nb := EnsureRegion(tw, ref.rx, ref.ry - 1);
    Push(ref.rx, ref.ry - 1, nb^.edgeRoom[EDGE_BOTTOM]);
  end;
end;

function TileWorldRegionCount(const tw: TTileWorld): longint;
begin
  TileWorldRegionCount := tw.live;
end;

procedure TileWorldFree(var tw: TTileWorld);
var
  i: longint;
begin
  for i := 0 to tw.cap - 1 do
    if tw.slotState[i] = 1 then begin
      Dispose(tw.slotReg[i]);
      tw.slotReg[i] := nil;
      tw.slotState[i] := 2;
    end;
  tw.live := 0;
end;

end.
