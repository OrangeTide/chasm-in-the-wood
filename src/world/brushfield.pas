unit brushfield;

{** The art field: the map as an explicit list of brush instances.

  Placement used to be re-decided every frame. The renderer walked the visible
  cells, asked the socket predicates where each brush belonged, and drew it. The
  decision never changed from one frame to the next, yet it was paid for on every
  one.

  Here the generator's tile output is turned into instances once per region: a
  brush id, a tile position, and a quarter-turn orientation, the shape the map
  architecture calls for (piece plus voxel position plus rotation; mirror is not
  needed by the current set and is left out). The renderer then draws the list, it
  does not rediscover it. An instance is a pure function of the generated tiles, so
  a region's list is emitted the first time it is drawn and kept; walking back to an
  evicted region re-emits the identical list.

  The list is derived through the same socket registry (brushdef) that collision
  reads, so the pieces drawn and the pieces blocked come from one source. Emission
  reads a one tile border into the neighbouring regions (a wall faces the solid
  across a seam, a corner post reads the four cells it stands between), which the
  streaming world supplies on demand.

  Each region owns the cells and the grid corners in [r*REGION .. r*REGION+REGION-1]
  on each axis, so every cell and every corner belongs to exactly one region and
  nothing is emitted twice at a seam. }

{$mode objfpc}{$H+}

interface

uses
  tilemap, tileworld, brushdef;

type
  { One placed piece. Rot is a quarter turn count whose meaning is set by the
    brush's style: for a wall panel it is the edge direction (0..3, the EDGE_*
    order); for a door or gate it is 0 along x or 1 along z; for a floor, stair, or
    post it is 0. }
  TBrushInst = record
    Brush: Byte;
    X, Y:  LongInt;
    Rot:   Byte;
  end;

  { A region's emitted instances. }
  PBrushList = ^TBrushList;
  TBrushList = record
    Rx, Ry: LongInt;
    Inst:   array of TBrushInst;
    N:      LongInt;
    Used:   Int64;
    Valid:  Boolean;
  end;

  { A small cache of region lists, enough for the view neighbourhood. Lists are
    pure functions of the world and region, so a plain capacity with least recently
    used replacement is all the bookkeeping needed. }
  PBrushField = ^TBrushField;
  TBrushField = record
    Slots: array of TBrushList;
    Clock: Int64;
  end;

{ The edge directions, as the neighbour offset each faces. Index is the wall panel
  Rot, and the canonical order north, west, south, east (see DrawWallPanel). }
const
  EDGE_DX: array[0..3] of LongInt = (0, -1, 0, 1);
  EDGE_DY: array[0..3] of LongInt = (-1, 0, 1, 0);

procedure BrushFieldInit(out bf: TBrushField);
{ Forget every cached list. Call after the world is rebuilt (a new depth, the town,
  a reload), since the tiles behind the lists have changed. }
procedure BrushFieldReset(var bf: TBrushField);
{ Drop the cached list for one region, so it re-emits on the next draw. Call when a
  tile in it changed, which in play means a door was opened. }
procedure BrushFieldInvalidate(var bf: TBrushField; rx, ry: LongInt);
{ The instance list for region (rx, ry), emitting it if it is not resident. The
  returned list is owned by the field and stays valid until the region is evicted,
  invalidated, or reset. }
function BrushFieldRegion(var bf: TBrushField; var tw: TTileWorld;
  rx, ry: LongInt): PBrushList;

{ Emit a region's instances into a caller supplied list, without the cache. Shared
  by the cache and by tests. }
procedure BrushEmitRegion(var tw: TTileWorld; rx, ry: LongInt; var list: TBrushList);

{ Find the blocking brush instance placed at grid corner (gx, gy), if any, and return
  its brush id. This is how collision reads the art field: it asks which placed piece
  intrudes at a corner, rather than re-deriving the pattern for itself. The owning
  region is emitted on demand. }
function BrushFieldBlockerAt(var bf: TBrushField; var tw: TTileWorld;
  gx, gy: LongInt; out brush: Byte): Boolean;

implementation

const
  SLOTS = 48;   { comfortably covers the regions a view window spans }

function DoorAlongZ(var tw: TTileWorld; tx, ty: LongInt): Boolean;
{ A door's wall runs north-south (the leaf spans z) when its two solid neighbours
  are above and below. The same solid predicate the other sockets use. }
begin
  DoorAlongZ := TileWorldSolid(tw, tx, ty - 1) and TileWorldSolid(tw, tx, ty + 1);
end;

procedure Append(var list: TBrushList; brush: Byte; x, y: LongInt; rot: Byte);
begin
  if list.N >= Length(list.Inst) then
    SetLength(list.Inst, (list.N + 16) * 2);
  list.Inst[list.N].Brush := brush;
  list.Inst[list.N].X := x;
  list.Inst[list.N].Y := y;
  list.Inst[list.N].Rot := rot;
  Inc(list.N);
end;

procedure BrushEmitRegion(var tw: TTileWorld; rx, ry: LongInt; var list: TBrushList);
var
  x0, y0, tx, ty, gx, gy, i, dir: LongInt;
  rot: Byte;
begin
  list.Rx := rx;
  list.Ry := ry;
  list.N := 0;
  x0 := rx * REGION;
  y0 := ry * REGION;
  { Cells and their edges. A solid cell shows nothing; the wall panels on its open
    neighbours are its visible faces. }
  for ty := y0 to y0 + REGION - 1 do
    for tx := x0 to x0 + REGION - 1 do begin
      if TileWorldSolid(tw, tx, ty) then continue;
      for i := 0 to High(DUNGEON_BRUSHES) do
        case DUNGEON_BRUSHES[i].Anchor of
          baCell:
            if SocketCell(DUNGEON_BRUSHES[i].Socket, tw, tx, ty) then begin
              rot := 0;
              case DUNGEON_BRUSHES[i].Style of
                stDoorSwing, stGate:
                  if DoorAlongZ(tw, tx, ty) then rot := 1;
              end;
              Append(list, i, tx, ty, rot);
            end;
          baEdge:
            for dir := 0 to 3 do
              if SocketEdge(DUNGEON_BRUSHES[i].Socket, tw, tx, ty,
                            EDGE_DX[dir], EDGE_DY[dir]) then
                Append(list, i, tx, ty, dir);
        end;
    end;
  { Grid corners owned by this region: a beam post where wall panels turn. }
  for gy := y0 to y0 + REGION - 1 do
    for gx := x0 to x0 + REGION - 1 do
      for i := 0 to High(DUNGEON_BRUSHES) do
        if (DUNGEON_BRUSHES[i].Anchor = baCorner) and
           SocketCorner(DUNGEON_BRUSHES[i].Socket, tw, gx, gy) then
          Append(list, i, gx, gy, 0);
  list.Valid := True;
end;

procedure BrushFieldInit(out bf: TBrushField);
var
  i: LongInt;
begin
  SetLength(bf.Slots, SLOTS);
  bf.Clock := 0;
  for i := 0 to SLOTS - 1 do begin
    bf.Slots[i].Valid := False;
    bf.Slots[i].N := 0;
    bf.Slots[i].Used := 0;
  end;
end;

procedure BrushFieldReset(var bf: TBrushField);
var
  i: LongInt;
begin
  for i := 0 to High(bf.Slots) do bf.Slots[i].Valid := False;
end;

procedure BrushFieldInvalidate(var bf: TBrushField; rx, ry: LongInt);
var
  i: LongInt;
begin
  for i := 0 to High(bf.Slots) do
    if bf.Slots[i].Valid and (bf.Slots[i].Rx = rx) and (bf.Slots[i].Ry = ry) then
      bf.Slots[i].Valid := False;
end;

function BrushFieldRegion(var bf: TBrushField; var tw: TTileWorld;
  rx, ry: LongInt): PBrushList;
var
  i, slot: LongInt;
  oldest: Int64;
begin
  Inc(bf.Clock);
  slot := -1;
  for i := 0 to High(bf.Slots) do
    if bf.Slots[i].Valid and (bf.Slots[i].Rx = rx) and (bf.Slots[i].Ry = ry) then begin
      slot := i;
      break;
    end;
  if slot < 0 then begin
    { Reuse a free slot, else the least recently used one. }
    oldest := High(Int64);
    for i := 0 to High(bf.Slots) do begin
      if not bf.Slots[i].Valid then begin slot := i; break; end;
      if bf.Slots[i].Used < oldest then begin oldest := bf.Slots[i].Used; slot := i; end;
    end;
    BrushEmitRegion(tw, rx, ry, bf.Slots[slot]);
  end;
  bf.Slots[slot].Used := bf.Clock;
  BrushFieldRegion := @bf.Slots[slot];
end;

function RegionOf(t: LongInt): LongInt;
{ The region index holding tile or corner coordinate t (floor division by REGION). }
begin
  if t >= 0 then RegionOf := t div REGION
  else RegionOf := -(((-t) + REGION - 1) div REGION);
end;

function BrushFieldBlockerAt(var bf: TBrushField; var tw: TTileWorld;
  gx, gy: LongInt; out brush: Byte): Boolean;
var
  list: PBrushList;
  k: LongInt;
begin
  BrushFieldBlockerAt := False;
  brush := 0;
  list := BrushFieldRegion(bf, tw, RegionOf(gx), RegionOf(gy));
  for k := 0 to list^.N - 1 do
    if DUNGEON_BRUSHES[list^.Inst[k].Brush].Blocks and
       (list^.Inst[k].X = gx) and (list^.Inst[k].Y = gy) then begin
      brush := list^.Inst[k].Brush;
      BrushFieldBlockerAt := True;
      exit;
    end;
end;

end.
