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
  is free of visible effect. Nothing outside holds a region Pointer across calls, so
  a region can be freed safely. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap, roomgraph, worldgen, themes, town;

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
    Rx, Ry: LongInt;
    Cells: array of Byte;
    Graph: TRoomGraph;
    LastUsed: Int64;   { recency clock value at last access }
    HasUp, HasDown: Boolean;        { stairs this region hosts, if any }
    UpX, UpY, DownX, DownY: LongInt;
    EdgeRoom: array[0..3] of LongInt;   { local room each seam crossing reaches }
  end;

  { A room's identity across the whole world: its region plus its local index. }
  TRoomRef = record
    Rx, Ry, Idx: LongInt;
  end;

  TTileWorld = record
    Base: QWord;                { the raw world seed, before the depth fold }
    Seed: QWord;                { effective seed, folded with the depth }
    Depth: LongInt;             { which dungeon level this world is }
    IsTown: Boolean;            { the surface hamlet, not a dungeon depth }
    TownLay: TTownLayout;       { the hamlet's landmarks, when IsTown }
    SlotKey: array of Int64;
    SlotReg: array of PRegion;
    SlotState: array of Byte;   { 0 empty, 1 used, 2 dead (tombstone) }
    Cap, Live, Filled: LongInt;
    Clock: Int64;
  end;

procedure TileWorldInit(out tw: TTileWorld; seed: QWord; depth: LongInt);
{ Initialise the surface hamlet instead of a dungeon depth. Region (0,0) is the town;
  everything beyond it is solid rock, so the hamlet is bounded. }
procedure TileWorldInitTown(out tw: TTileWorld; seed: QWord);
function TileWorldIsTown(const tw: TTileWorld): Boolean;
function TileWorldTownLayout(const tw: TTileWorld): TTownLayout;
function TileAt(var tw: TTileWorld; tx, ty: LongInt): Byte;
function TileWorldWalkable(var tw: TTileWorld; tx, ty: LongInt): Boolean;
procedure TileWorldSpawn(var tw: TTileWorld; out sx, sy: LongInt);
{ The stairs in a given region, if it hosts them. Descending from a region's
  down-stair lands on the same region's up-stair one depth down, and ascending
  reverses it, so the player arrives standing on the matching stair. }
function TileWorldRegionUpStair(var tw: TTileWorld; rx, ry: LongInt;
  out sx, sy: LongInt): Boolean;
function TileWorldRegionDownStair(var tw: TTileWorld; rx, ry: LongInt;
  out sx, sy: LongInt): Boolean;
function TileWorldDepth(const tw: TTileWorld): LongInt;
function TileWorldThemeAt(const tw: TTileWorld; tx, ty: LongInt): LongInt;
{ The room containing a tile, as a world-wide reference, or False for a corridor or
  rock. The stitched world graph is reached through this and the neighbours below. }
function TileWorldRoomAt(var tw: TTileWorld; tx, ty: LongInt;
  out ref: TRoomRef): Boolean;
{ The rooms directly linked to a room: its region's own portals, plus the seam
  crossings that join it to the rooms in the neighbouring regions. Fills up to
  Length(refs) entries and sets n. This is where separate regions and zones stitch
  into one connected graph. }
procedure TileWorldRoomNeighbours(var tw: TTileWorld; const ref: TRoomRef;
  var refs: array of TRoomRef; out n: LongInt);
{ Room access for entity placement. Both generate the region if it is not resident. }
function TileWorldRegionRoomCount(var tw: TTileWorld; rx, ry: LongInt): LongInt;
function TileWorldRoomCenter(var tw: TTileWorld; const ref: TRoomRef;
  out gx, gy: LongInt): Boolean;
function TileWorldRegionCount(const tw: TTileWorld): LongInt;
procedure TileWorldFree(var tw: TTileWorld);

implementation

function FloorDiv(a, b: LongInt): LongInt;
begin
  if a >= 0 then FloorDiv := a div b
  else FloorDiv := -(((-a) + b - 1) div b);
end;

function Mix(seed: QWord; a, b, c: LongInt): QWord;
{ A small FNV-style mix of the seed and three integers. }
var
  h: QWord;
begin
  h := seed xor QWord($CBF29CE484222325);
  h := (h xor QWord(LongWord(a))) * QWord($100000001B3);
  h := (h xor QWord(LongWord(b))) * QWord($100000001B3);
  h := (h xor QWord(LongWord(c))) * QWord($100000001B3);
  Mix := h;
end;

function EdgePos(seed: QWord; a, b, axis: LongInt): LongInt;
{ A crossing position along a shared edge, off the corners. Both regions that share
  the edge pass its canonical (a, b, axis), so they agree. }
begin
  EdgePos := LongInt((Mix(seed, a, b, axis + 1) shr 33) mod QWord(REGION - 2)) + 1;
end;

{ ---- region hash with tombstones ---- }

function PackR(rx, ry: LongInt): Int64;
begin
  PackR := (Int64(LongWord(rx)) shl 32) or Int64(LongWord(ry));
end;

procedure HashInit(var tw: TTileWorld; cap: LongInt);
var
  i: LongInt;
begin
  tw.Cap := cap; tw.Live := 0; tw.Filled := 0;
  SetLength(tw.SlotKey, cap);
  SetLength(tw.SlotReg, cap);
  SetLength(tw.SlotState, cap);
  for i := 0 to cap - 1 do begin
    tw.SlotState[i] := 0;
    tw.SlotReg[i] := nil;
  end;
end;

function HashIndex(const tw: TTileWorld; key: Int64): LongInt;
begin
  HashIndex := LongInt((QWord(key) * QWord($9E3779B97F4A7C15)) shr 40) and (tw.Cap - 1);
end;

function HashSlot(const tw: TTileWorld; key: Int64): LongInt;
{ The used slot holding key, or -1. }
var
  idx: LongInt;
begin
  idx := HashIndex(tw, key);
  while tw.SlotState[idx] <> 0 do begin
    if (tw.SlotState[idx] = 1) and (tw.SlotKey[idx] = key) then begin
      HashSlot := idx; exit;
    end;
    idx := (idx + 1) and (tw.Cap - 1);
  end;
  HashSlot := -1;
end;

procedure HashGrow(var tw: TTileWorld); forward;

procedure HashInsert(var tw: TTileWorld; key: Int64; reg: PRegion);
var
  idx, dead: LongInt;
begin
  if (tw.Filled + 1) * 10 > tw.Cap * 7 then HashGrow(tw);
  idx := HashIndex(tw, key);
  dead := -1;
  while tw.SlotState[idx] <> 0 do begin
    if (tw.SlotState[idx] = 2) and (dead < 0) then dead := idx;
    idx := (idx + 1) and (tw.Cap - 1);
  end;
  if dead >= 0 then idx := dead
  else Inc(tw.Filled);
  tw.SlotKey[idx] := key;
  tw.SlotReg[idx] := reg;
  tw.SlotState[idx] := 1;
  Inc(tw.Live);
end;

procedure HashGrow(var tw: TTileWorld);
var
  oldKey: array of Int64;
  oldReg: array of PRegion;
  oldState: array of Byte;
  i: LongInt;
begin
  oldKey := tw.SlotKey; oldReg := tw.SlotReg; oldState := tw.SlotState;
  HashInit(tw, tw.Cap * 2);
  for i := 0 to length(oldState) - 1 do
    if oldState[i] = 1 then HashInsert(tw, oldKey[i], oldReg[i]);
end;

procedure EvictLRU(var tw: TTileWorld);
{ Free the least recently used region. The just-created region holds the newest
  clock value, so it is never the victim. }
var
  i, victim: LongInt;
  best: Int64;
begin
  victim := -1;
  best := high(Int64);
  for i := 0 to tw.Cap - 1 do
    if (tw.SlotState[i] = 1) and (tw.SlotReg[i]^.LastUsed < best) then begin
      best := tw.SlotReg[i]^.LastUsed;
      victim := i;
    end;
  if victim < 0 then exit;
  Dispose(tw.SlotReg[victim]);
  tw.SlotReg[victim] := nil;
  tw.SlotState[victim] := 2;
  Dec(tw.Live);
end;

{ ---- region generation ---- }

procedure SetCell(reg: PRegion; x, y: LongInt; v: Byte);
begin
  if (x >= 0) and (y >= 0) and (x < REGION) and (y < REGION) then
    reg^.Cells[x + y * REGION] := v;
end;

function ConnectEdge(reg: PRegion; px, py: LongInt): LongInt;
{ Carve an L-corridor from the nearest room's centre out to the edge tile, so the
  crossing connects to the region's room network. Returns that room's local index, or
  -1 when the region has no rooms, which is what stitches the seam to a neighbour. }
var
  i, best, bestD, d, ax, ay, cxc, cyc, x, y: LongInt;
begin
  if reg^.Graph.Nrooms = 0 then begin
    ConnectEdge := -1;
    exit;
  end;
  best := 0; bestD := high(LongInt);
  for i := 0 to reg^.Graph.Nrooms - 1 do begin
    cxc := RoomCenterX(reg^.Graph.Rooms[i]);
    cyc := RoomCenterY(reg^.Graph.Rooms[i]);
    d := abs(cxc - px) + abs(cyc - py);
    if d < bestD then begin bestD := d; best := i; end;
  end;
  ax := RoomCenterX(reg^.Graph.Rooms[best]);
  ay := RoomCenterY(reg^.Graph.Rooms[best]);
  if ax <= px then for x := ax to px do SetCell(reg, x, ay, TILE_FLOOR)
  else for x := px to ax do SetCell(reg, x, ay, TILE_FLOOR);
  if ay <= py then for y := ay to py do SetCell(reg, px, y, TILE_FLOOR)
  else for y := py to ay do SetCell(reg, px, y, TILE_FLOOR);
  ConnectEdge := best;
end;

function RegionGenParams(const tw: TTileWorld; rx, ry: LongInt): TGenParams;
{ The carving parameters for a region come from the theme of the zone it sits in. }
var
  th: TTheme;
begin
  th := ThemeTable[ThemeIndex(tw.Seed, rx, ry)];
  RegionGenParams.MinLeaf := th.MinLeaf;
  RegionGenParams.MinRoom := th.MinRoom;
  RegionGenParams.MaxDepth := th.MaxDepth;
end;

procedure GenerateTownRegion(const tw: TTileWorld; reg: PRegion);
{ Region (0,0) is the hamlet; every other region is solid rock, which bounds it. The
  chasm is recorded as this region's down-stair, and the spawn tile as its up-stair, so
  the descent and the return reuse the dungeon's stair plumbing. }
var
  lay: TTownLayout;
  k, i: LongInt;
begin
  SetLength(reg^.Cells, REGION * REGION);
  RoomGraphInit(reg^.Graph);
  for i := 0 to 3 do reg^.EdgeRoom[i] := -1;
  reg^.HasUp := False;
  reg^.HasDown := False;
  if (reg^.Rx = 0) and (reg^.Ry = 0) then begin
    TownBuild(reg^.Cells, REGION, REGION, lay);
    reg^.DownX := lay.Chasm.X; reg^.DownY := lay.Chasm.Y;
    reg^.HasDown := True;
    reg^.UpX := lay.Spawn.X; reg^.UpY := lay.Spawn.Y;
    reg^.HasUp := True;
  end else
    for k := 0 to REGION * REGION - 1 do reg^.Cells[k] := TILE_ROCK;
end;

procedure GenerateRegion(const tw: TTileWorld; reg: PRegion);
var
  r: TRng;
  sx, sy: LongInt;
begin
  if tw.IsTown then begin
    GenerateTownRegion(tw, reg);
    exit;
  end;
  SetLength(reg^.Cells, REGION * REGION);
  RngSeed(r, Mix(tw.Seed, reg^.Rx, reg^.Ry, 0));
  CarveRooms(reg^.Cells, REGION, REGION, r, reg^.Graph, sx, sy,
             RegionGenParams(tw, reg^.Rx, reg^.Ry));
  { Four seam crossings, each at a position both neighbours agree on. Record which
    room each reaches, so the seam can stitch to the neighbour's matching edge room. }
  reg^.EdgeRoom[EDGE_RIGHT] :=
    ConnectEdge(reg, REGION - 1, EdgePos(tw.Seed, reg^.Rx, reg^.Ry, 0));
  reg^.EdgeRoom[EDGE_LEFT] :=
    ConnectEdge(reg, 0, EdgePos(tw.Seed, reg^.Rx - 1, reg^.Ry, 0));
  reg^.EdgeRoom[EDGE_BOTTOM] :=
    ConnectEdge(reg, EdgePos(tw.Seed, reg^.Rx, reg^.Ry, 1), REGION - 1);
  reg^.EdgeRoom[EDGE_TOP] :=
    ConnectEdge(reg, EdgePos(tw.Seed, reg^.Rx, reg^.Ry - 1, 1), 0);
  LayWalls(reg^.Cells, REGION, REGION);
  PlaceDoors(reg^.Cells, REGION, REGION);
end;

function StairRegion(base: QWord; d, rx, ry: LongInt): Boolean;
{ Whether depth d's region (rx, ry) hosts a down-stair. About one region in four,
  plus the origin on every depth so there is always a reachable descent. The result
  depends on the raw seed and the depth, not the folded per-depth seed, so depth d+1
  can compute depth d's answer when it places its matching up-stairs. }
begin
  if (rx = 0) and (ry = 0) then StairRegion := True
  else StairRegion :=
    (Mix(base xor QWord($D1B54A32D192ED03), d, rx, ry) shr 33) mod 4 = 0;
end;

procedure PlaceStairs(const tw: TTileWorld; reg: PRegion);
{ Scatter stairs across the world. A region hosts a down-stair when StairRegion says
  so, and an up-stair when the region one depth up hosted a down-stair, which keeps a
  descent and the ascent back lined up. Stairs sit at room centres, so the player
  arrives standing on one. }
var
  r0, rN, lx, ly: LongInt;
begin
  reg^.HasUp := False;
  reg^.HasDown := False;
  if reg^.Graph.Nrooms = 0 then exit;
  r0 := 0;
  rN := reg^.Graph.Nrooms - 1;
  { Carve at the room centre (region-local), and store the stair's global tile. }
  if StairRegion(tw.Base, tw.Depth, reg^.Rx, reg^.Ry) then begin
    lx := RoomCenterX(reg^.Graph.Rooms[rN]);
    ly := RoomCenterY(reg^.Graph.Rooms[rN]);
    SetCell(reg, lx, ly, TILE_STAIRS_DOWN);
    reg^.DownX := reg^.Rx * REGION + lx;
    reg^.DownY := reg^.Ry * REGION + ly;
    reg^.HasDown := True;
  end;
  { Up-stairs: on deeper levels, the match for the level above's down-stair. On depth
    0 the origin region instead hosts the climb back to the surface hamlet. }
  if (rN <> r0) and
     ( ((tw.Depth > 0) and StairRegion(tw.Base, tw.Depth - 1, reg^.Rx, reg^.Ry)) or
       ((tw.Depth = 0) and (reg^.Rx = 0) and (reg^.Ry = 0)) ) then begin
    lx := RoomCenterX(reg^.Graph.Rooms[r0]);
    ly := RoomCenterY(reg^.Graph.Rooms[r0]);
    SetCell(reg, lx, ly, TILE_STAIRS_UP);
    reg^.UpX := reg^.Rx * REGION + lx;
    reg^.UpY := reg^.Ry * REGION + ly;
    reg^.HasUp := True;
  end;
end;

function EnsureRegion(var tw: TTileWorld; rx, ry: LongInt): PRegion;
var
  slot: LongInt;
  reg: PRegion;
begin
  Inc(tw.Clock);
  slot := HashSlot(tw, PackR(rx, ry));
  if slot >= 0 then begin
    tw.SlotReg[slot]^.LastUsed := tw.Clock;
    EnsureRegion := tw.SlotReg[slot];
    exit;
  end;
  New(reg);
  reg^.Rx := rx; reg^.Ry := ry;
  reg^.LastUsed := tw.Clock;
  GenerateRegion(tw, reg);
  if not tw.IsTown then PlaceStairs(tw, reg);
  HashInsert(tw, PackR(rx, ry), reg);
  if tw.Live > MAX_REGIONS then EvictLRU(tw);
  EnsureRegion := reg;
end;

{ ---- public ---- }

procedure TileWorldInit(out tw: TTileWorld; seed: QWord; depth: LongInt);
begin
  tw.Base := seed;
  tw.Depth := depth;
  tw.IsTown := False;
  { Fold the depth into the seed so each depth is a different dungeon. }
  tw.Seed := Mix(seed, depth, 0, 0);
  tw.Clock := 0;
  HashInit(tw, 64);
end;

procedure TileWorldInitTown(out tw: TTileWorld; seed: QWord);
var
  tmp: array of Byte;
begin
  tw.Base := seed;
  tw.Depth := 0;
  tw.IsTown := True;
  tw.Seed := Mix(seed, 0, 0, 0);
  tw.Clock := 0;
  { Build the layout once so the landmark accessors work before region (0,0) loads. }
  SetLength(tmp, REGION * REGION);
  TownBuild(tmp, REGION, REGION, tw.TownLay);
  HashInit(tw, 64);
end;

function TileWorldIsTown(const tw: TTileWorld): Boolean;
begin
  TileWorldIsTown := tw.IsTown;
end;

function TileWorldTownLayout(const tw: TTileWorld): TTownLayout;
begin
  TileWorldTownLayout := tw.TownLay;
end;

function TileAt(var tw: TTileWorld; tx, ty: LongInt): Byte;
var
  rx, ry: LongInt;
  reg: PRegion;
begin
  rx := FloorDiv(tx, REGION);
  ry := FloorDiv(ty, REGION);
  reg := EnsureRegion(tw, rx, ry);
  TileAt := reg^.Cells[(tx - rx * REGION) + (ty - ry * REGION) * REGION];
end;

function TileWorldWalkable(var tw: TTileWorld; tx, ty: LongInt): Boolean;
var
  t: Byte;
begin
  t := TileAt(tw, tx, ty);
  TileWorldWalkable := (t = TILE_FLOOR) or (t = TILE_DOOR) or
                       (t = TILE_STAIRS_DOWN) or (t = TILE_STAIRS_UP);
end;

procedure TileWorldSpawn(var tw: TTileWorld; out sx, sy: LongInt);
var
  reg: PRegion;
begin
  if tw.IsTown then begin
    sx := tw.TownLay.Spawn.X; sy := tw.TownLay.Spawn.Y;
    exit;
  end;
  reg := EnsureRegion(tw, 0, 0);
  if reg^.Graph.Nrooms > 0 then begin
    sx := RoomCenterX(reg^.Graph.Rooms[0]);
    sy := RoomCenterY(reg^.Graph.Rooms[0]);
  end else begin
    sx := REGION div 2; sy := REGION div 2;
  end;
end;

function TileWorldRegionUpStair(var tw: TTileWorld; rx, ry: LongInt;
  out sx, sy: LongInt): Boolean;
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, rx, ry);
  sx := reg^.UpX; sy := reg^.UpY;
  TileWorldRegionUpStair := reg^.HasUp;
end;

function TileWorldRegionDownStair(var tw: TTileWorld; rx, ry: LongInt;
  out sx, sy: LongInt): Boolean;
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, rx, ry);
  sx := reg^.DownX; sy := reg^.DownY;
  TileWorldRegionDownStair := reg^.HasDown;
end;

function TileWorldDepth(const tw: TTileWorld): LongInt;
begin
  TileWorldDepth := tw.Depth;
end;

function TileWorldThemeAt(const tw: TTileWorld; tx, ty: LongInt): LongInt;
{ The theme index of the tile's region. Pure: it reads no region, so it never
  triggers generation. The hamlet uses its own theme throughout. }
begin
  if tw.IsTown then
    TileWorldThemeAt := THEME_TOWN
  else
    TileWorldThemeAt := ThemeIndex(tw.Seed, FloorDiv(tx, REGION), FloorDiv(ty, REGION));
end;

function TileWorldRoomAt(var tw: TTileWorld; tx, ty: LongInt;
  out ref: TRoomRef): Boolean;
var
  rx, ry, li: LongInt;
  reg: PRegion;
begin
  rx := FloorDiv(tx, REGION);
  ry := FloorDiv(ty, REGION);
  reg := EnsureRegion(tw, rx, ry);
  li := RoomGraphRoomAt(reg^.Graph, tx - rx * REGION, ty - ry * REGION);
  if li < 0 then begin
    TileWorldRoomAt := False;
    exit;
  end;
  ref.Rx := rx; ref.Ry := ry; ref.Idx := li;
  TileWorldRoomAt := True;
end;

procedure TileWorldRoomNeighbours(var tw: TTileWorld; const ref: TRoomRef;
  var refs: array of TRoomRef; out n: LongInt);
var
  reg, nb: PRegion;
  i, cap: LongInt;
  edge: array[0..3] of LongInt;

  procedure Push(rx, ry, idx: LongInt);
  begin
    if (idx >= 0) and (n < cap) then begin
      refs[n].Rx := rx; refs[n].Ry := ry; refs[n].Idx := idx;
      Inc(n);
    end;
  end;

begin
  n := 0;
  cap := Length(refs);
  reg := EnsureRegion(tw, ref.Rx, ref.Ry);
  { Portals inside the room's own region. }
  for i := 0 to reg^.Graph.Nportals - 1 do begin
    if reg^.Graph.Portals[i].A = ref.Idx then
      Push(ref.Rx, ref.Ry, reg^.Graph.Portals[i].B)
    else if reg^.Graph.Portals[i].B = ref.Idx then
      Push(ref.Rx, ref.Ry, reg^.Graph.Portals[i].A);
  end;
  { Copy the edge rooms before ensuring neighbours, which may move region pointers. }
  for i := 0 to 3 do edge[i] := reg^.EdgeRoom[i];
  { Seam crossings: if this room reaches an edge, stitch to the matching edge room of
    the neighbouring region across that seam. }
  if edge[EDGE_RIGHT] = ref.Idx then begin
    nb := EnsureRegion(tw, ref.Rx + 1, ref.Ry);
    Push(ref.Rx + 1, ref.Ry, nb^.EdgeRoom[EDGE_LEFT]);
  end;
  if edge[EDGE_LEFT] = ref.Idx then begin
    nb := EnsureRegion(tw, ref.Rx - 1, ref.Ry);
    Push(ref.Rx - 1, ref.Ry, nb^.EdgeRoom[EDGE_RIGHT]);
  end;
  if edge[EDGE_BOTTOM] = ref.Idx then begin
    nb := EnsureRegion(tw, ref.Rx, ref.Ry + 1);
    Push(ref.Rx, ref.Ry + 1, nb^.EdgeRoom[EDGE_TOP]);
  end;
  if edge[EDGE_TOP] = ref.Idx then begin
    nb := EnsureRegion(tw, ref.Rx, ref.Ry - 1);
    Push(ref.Rx, ref.Ry - 1, nb^.EdgeRoom[EDGE_BOTTOM]);
  end;
end;

function TileWorldRegionRoomCount(var tw: TTileWorld; rx, ry: LongInt): LongInt;
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, rx, ry);
  TileWorldRegionRoomCount := reg^.Graph.Nrooms;
end;

function TileWorldRoomCenter(var tw: TTileWorld; const ref: TRoomRef;
  out gx, gy: LongInt): Boolean;
var
  reg: PRegion;
begin
  reg := EnsureRegion(tw, ref.Rx, ref.Ry);
  if (ref.Idx < 0) or (ref.Idx >= reg^.Graph.Nrooms) then begin
    gx := 0; gy := 0;
    TileWorldRoomCenter := False;
    exit;
  end;
  gx := ref.Rx * REGION + RoomCenterX(reg^.Graph.Rooms[ref.Idx]);
  gy := ref.Ry * REGION + RoomCenterY(reg^.Graph.Rooms[ref.Idx]);
  TileWorldRoomCenter := True;
end;

function TileWorldRegionCount(const tw: TTileWorld): LongInt;
begin
  TileWorldRegionCount := tw.Live;
end;

procedure TileWorldFree(var tw: TTileWorld);
var
  i: LongInt;
begin
  for i := 0 to tw.Cap - 1 do
    if tw.SlotState[i] = 1 then begin
      Dispose(tw.SlotReg[i]);
      tw.SlotReg[i] := nil;
      tw.SlotState[i] := 2;
    end;
  tw.Live := 0;
end;

end.
