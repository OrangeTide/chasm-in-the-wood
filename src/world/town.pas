unit town;
{ The surface hamlet of Brackenridge, carved into one region of tiles. The town is a   }
{ bounded place, unlike the unbounded dungeon: a walled green with a handful of         }
{ timber buildings and, near its heart, the chasm that descends into the dungeon. The   }
{ layout is fixed, so the hamlet reads the same every visit. All of its landmarks, the  }
{ spawn, the chasm, and where each townsperson stands, are returned in one record so    }
{ the game layer can place the townsfolk without repeating the coordinates.             }

{$mode objfpc}{$H+}

interface

uses
  tilemap;

type
  TTownSpot = record
    X, Y: LongInt;
  end;

  TTownLayout = record
    Spawn, Chasm: TTownSpot;
    Innkeeper, Trader, Reeve, Villager: TTownSpot;
  end;

{ Carve the hamlet into a w by h cell array (floor, wall, door, and the chasm as a
  down-stair) and report its landmarks. }
procedure TownBuild(var cells: array of Byte; w, h: LongInt; out lay: TTownLayout);

implementation

function Spot(x, y: LongInt): TTownSpot;
begin
  Spot.X := x; Spot.Y := y;
end;

procedure TownBuild(var cells: array of Byte; w, h: LongInt; out lay: TTownLayout);

  procedure Put(x, y: LongInt; v: Byte);
  begin
    if (x >= 0) and (y >= 0) and (x < w) and (y < h) then cells[x + y * w] := v;
  end;

  procedure Building(x0, y0, x1, y1, doorX, doorY: LongInt);
  { A timber house: a wall rectangle with a floor interior and one door. }
  var
    x, y: LongInt;
  begin
    for x := x0 to x1 do begin Put(x, y0, TILE_WALL); Put(x, y1, TILE_WALL); end;
    for y := y0 to y1 do begin Put(x0, y, TILE_WALL); Put(x1, y, TILE_WALL); end;
    for y := y0 + 1 to y1 - 1 do
      for x := x0 + 1 to x1 - 1 do Put(x, y, TILE_FLOOR);
    Put(doorX, doorY, TILE_DOOR);
  end;

var
  x, y: LongInt;
begin
  { Green ground, framed by a boundary wall so the hamlet is enclosed. }
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
      if (x = 0) or (y = 0) or (x = w - 1) or (y = h - 1) then
        cells[x + y * w] := TILE_WALL
      else
        cells[x + y * w] := TILE_FLOOR;

  { Four buildings around a central green. Door coordinates face the green. }
  Building(5, 5, 16, 13, 10, 13);      { the inn, north-west }
  Building(31, 5, 42, 13, 36, 13);     { the trader's stall, north-east }
  Building(5, 34, 17, 43, 11, 34);     { the reeve's hall, south-west }
  Building(31, 34, 42, 43, 36, 34);    { a villager's house, south-east }

  { The chasm at the heart of the green, and the spawn just north of it. }
  lay.Chasm := Spot(24, 25);
  Put(lay.Chasm.X, lay.Chasm.Y, TILE_STAIRS_DOWN);
  lay.Spawn := Spot(24, 20);

  { Each townsperson stands a step outside their door, on the green. }
  lay.Innkeeper := Spot(10, 15);
  lay.Trader    := Spot(36, 15);
  lay.Reeve     := Spot(11, 32);
  lay.Villager  := Spot(36, 32);
end;

end.
