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
    x, y, w, h: longint;   { tile-space rectangle }
  end;

  TPortal = record
    a, b: longint;         { room indices this portal joins }
    tx, ty: longint;       { a tile on the connection }
  end;

  TRoomGraph = record
    rooms: array of TRoom;
    nrooms: longint;
    portals: array of TPortal;
    nportals: longint;
  end;

procedure RoomGraphInit(out gph: TRoomGraph);
function RoomGraphAddRoom(var gph: TRoomGraph; x, y, w, h: longint): longint;
procedure RoomGraphAddPortal(var gph: TRoomGraph; a, b, tx, ty: longint);
function RoomCenterX(const r: TRoom): longint;
function RoomCenterY(const r: TRoom): longint;
function RoomGraphRoomAt(const gph: TRoomGraph; tx, ty: longint): longint;

implementation

procedure RoomGraphInit(out gph: TRoomGraph);
begin
  gph.nrooms := 0;
  gph.nportals := 0;
  SetLength(gph.rooms, 0);
  SetLength(gph.portals, 0);
end;

function RoomGraphAddRoom(var gph: TRoomGraph; x, y, w, h: longint): longint;
begin
  if gph.nrooms >= length(gph.rooms) then
    SetLength(gph.rooms, gph.nrooms * 2 + 8);
  gph.rooms[gph.nrooms].x := x; gph.rooms[gph.nrooms].y := y;
  gph.rooms[gph.nrooms].w := w; gph.rooms[gph.nrooms].h := h;
  RoomGraphAddRoom := gph.nrooms;
  Inc(gph.nrooms);
end;

procedure RoomGraphAddPortal(var gph: TRoomGraph; a, b, tx, ty: longint);
begin
  if gph.nportals >= length(gph.portals) then
    SetLength(gph.portals, gph.nportals * 2 + 8);
  gph.portals[gph.nportals].a := a; gph.portals[gph.nportals].b := b;
  gph.portals[gph.nportals].tx := tx; gph.portals[gph.nportals].ty := ty;
  Inc(gph.nportals);
end;

function RoomCenterX(const r: TRoom): longint;
begin
  RoomCenterX := r.x + r.w div 2;
end;

function RoomCenterY(const r: TRoom): longint;
begin
  RoomCenterY := r.y + r.h div 2;
end;

function RoomGraphRoomAt(const gph: TRoomGraph; tx, ty: longint): longint;
{ The room whose rectangle contains the tile, or -1 (a corridor or rock). }
var
  i: longint;
begin
  RoomGraphRoomAt := -1;
  for i := 0 to gph.nrooms - 1 do
    if (tx >= gph.rooms[i].x) and (ty >= gph.rooms[i].y) and
       (tx < gph.rooms[i].x + gph.rooms[i].w) and
       (ty < gph.rooms[i].y + gph.rooms[i].h) then begin
      RoomGraphRoomAt := i;
      exit;
    end;
end;

end.
