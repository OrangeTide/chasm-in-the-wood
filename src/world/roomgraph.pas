unit roomgraph;

{** Rooms and the portals between them.

  The dungeon generator records each room as a node and each corridor as a portal
  edge joining two rooms. Each region builds its own graph in region-local
  coordinates; the tile world stitches these per-region graphs together at the seam
  crossings into one connected world graph, which worldgraph then traverses.

  Rooms are tile-space rectangles. A portal stores the two rooms it joins and a
  representative tile where they connect. }

{$mode objfpc}{$H+}

interface

type
  TRoom = record
    X, Y, W, H: LongInt;   { tile-space rectangle }
  end;

  TPortal = record
    A, B: LongInt;         { room indices this portal joins }
    Tx, Ty: LongInt;       { a tile on the connection }
  end;

  TRoomGraph = record
    Rooms: array of TRoom;
    Nrooms: LongInt;
    Portals: array of TPortal;
    Nportals: LongInt;
  end;

procedure RoomGraphInit(out gph: TRoomGraph);
function RoomGraphAddRoom(var gph: TRoomGraph; x, y, w, h: LongInt): LongInt;
procedure RoomGraphAddPortal(var gph: TRoomGraph; a, b, tx, ty: LongInt);
function RoomCenterX(const r: TRoom): LongInt;
function RoomCenterY(const r: TRoom): LongInt;
function RoomGraphRoomAt(const gph: TRoomGraph; tx, ty: LongInt): LongInt;

implementation

procedure RoomGraphInit(out gph: TRoomGraph);
begin
  gph.Nrooms := 0;
  gph.Nportals := 0;
  SetLength(gph.Rooms, 0);
  SetLength(gph.Portals, 0);
end;

function RoomGraphAddRoom(var gph: TRoomGraph; x, y, w, h: LongInt): LongInt;
begin
  if gph.Nrooms >= length(gph.Rooms) then
    SetLength(gph.Rooms, gph.Nrooms * 2 + 8);
  gph.Rooms[gph.Nrooms].X := x; gph.Rooms[gph.Nrooms].Y := y;
  gph.Rooms[gph.Nrooms].W := w; gph.Rooms[gph.Nrooms].H := h;
  RoomGraphAddRoom := gph.Nrooms;
  Inc(gph.Nrooms);
end;

procedure RoomGraphAddPortal(var gph: TRoomGraph; a, b, tx, ty: LongInt);
begin
  if gph.Nportals >= length(gph.Portals) then
    SetLength(gph.Portals, gph.Nportals * 2 + 8);
  gph.Portals[gph.Nportals].A := a; gph.Portals[gph.Nportals].B := b;
  gph.Portals[gph.Nportals].Tx := tx; gph.Portals[gph.Nportals].Ty := ty;
  Inc(gph.Nportals);
end;

function RoomCenterX(const r: TRoom): LongInt;
begin
  RoomCenterX := r.X + r.W div 2;
end;

function RoomCenterY(const r: TRoom): LongInt;
begin
  RoomCenterY := r.Y + r.H div 2;
end;

function RoomGraphRoomAt(const gph: TRoomGraph; tx, ty: LongInt): LongInt;
{ The room whose rectangle contains the tile, or -1 (a corridor or rock). }
var
  i: LongInt;
begin
  RoomGraphRoomAt := -1;
  for i := 0 to gph.Nrooms - 1 do
    if (tx >= gph.Rooms[i].X) and (ty >= gph.Rooms[i].Y) and
       (tx < gph.Rooms[i].X + gph.Rooms[i].W) and
       (ty < gph.Rooms[i].Y + gph.Rooms[i].H) then begin
      RoomGraphRoomAt := i;
      exit;
    end;
end;

end.
