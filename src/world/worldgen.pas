unit worldgen;

{** Hierarchical dungeon generation.

  A binary space partition splits an area into leaves, each leaf gets a room, and
  sibling subtrees are joined by corridors as the recursion unwinds. Rooms and
  corridors are carved as floor; a separate pass lays a wall ring around the carved
  space. This is the bottom of the generation hierarchy, region down to rooms.

  The carving primitives work on a flat tile buffer so they serve both a Single
  bounded level (GenerateDungeon, used by tests) and the per-region generation of
  the streaming tile world, which carves rooms, adds seam connections, then walls.
  The generator is seeded, so a seed reproduces a level. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap, roomgraph, tilesock;

type
  { How a region is carved: the partition stops at minLeaf or maxDepth, and each
    room is at least minRoom on a side. A theme supplies these to vary room size
    and density from one zone to the next. }
  TGenParams = record
    MinLeaf, MinRoom, MaxDepth: LongInt;
  end;

{ The baseline carving parameters, used by the bounded level and as a fallback. }
function DefaultGenParams: TGenParams;

{ Carve rooms and connecting corridors into a cw*ch rock buffer, recording the
  room/portal graph and the spawn tile (the first room's centre). }
procedure CarveRooms(var cells: array of Byte; cw, ch: LongInt; var r: TRng;
  out gph: TRoomGraph; out spawnX, spawnY: LongInt; const gp: TGenParams);

{ Dress a carved rock/floor buffer: lay the wall ring, then cut doors through it.
  This is the socket driven boundary pass. Each step is a rule in DUNGEON_DRESS
  (see the implementation), a socket paired with the tile it sets, applied in
  order over the whole buffer. }
procedure DressDungeon(var cells: array of Byte; cw, ch: LongInt);

{ A Single bounded level: rock, carve, walls. }
procedure GenerateDungeon(out m: TTileMap; out gph: TRoomGraph;
  w, h: LongInt; seed: QWord);

implementation

const
  MARGIN = 1;

function DefaultGenParams: TGenParams;
begin
  DefaultGenParams.MinLeaf := 9;
  DefaultGenParams.MinRoom := 4;
  DefaultGenParams.MaxDepth := 5;
end;

procedure CarveRooms(var cells: array of Byte; cw, ch: LongInt; var r: TRng;
  out gph: TRoomGraph; out spawnX, spawnY: LongInt; const gp: TGenParams);
var
  haveSpawn: Boolean;
  sx, sy: LongInt;

  procedure SetF(x, y: LongInt; v: Byte);
  begin
    if (x >= 0) and (y >= 0) and (x < cw) and (y < ch) then
      cells[x + y * cw] := v;
  end;

  procedure CarveRect(x0, y0, x1, y1: LongInt);
  var
    x, y: LongInt;
  begin
    for y := y0 to y1 do
      for x := x0 to x1 do
        SetF(x, y, TILE_FLOOR);
  end;

  procedure Corridor(ra, rb: LongInt);
  var
    ax, ay, bx, by, x, y: LongInt;
  begin
    ax := RoomCenterX(gph.Rooms[ra]); ay := RoomCenterY(gph.Rooms[ra]);
    bx := RoomCenterX(gph.Rooms[rb]); by := RoomCenterY(gph.Rooms[rb]);
    if ax <= bx then for x := ax to bx do SetF(x, ay, TILE_FLOOR)
    else for x := bx to ax do SetF(x, ay, TILE_FLOOR);
    if ay <= by then for y := ay to by do SetF(bx, y, TILE_FLOOR)
    else for y := by to ay do SetF(bx, y, TILE_FLOOR);
    RoomGraphAddPortal(gph, ra, rb, (ax + bx) div 2, (ay + by) div 2);
  end;

  function CarveRoom(x, y, lw, lh: LongInt): LongInt;
  var
    rw, rh, rx, ry: LongInt;
  begin
    rw := RngRange(r, gp.MinRoom, lw - 2 * MARGIN);
    rh := RngRange(r, gp.MinRoom, lh - 2 * MARGIN);
    if rw < 1 then rw := 1;
    if rh < 1 then rh := 1;
    rx := x + MARGIN + RngBelow(r, lw - 2 * MARGIN - rw + 1);
    ry := y + MARGIN + RngBelow(r, lh - 2 * MARGIN - rh + 1);
    CarveRect(rx, ry, rx + rw - 1, ry + rh - 1);
    CarveRoom := RoomGraphAddRoom(gph, rx, ry, rw, rh);
    if not haveSpawn then begin
      sx := rx + rw div 2; sy := ry + rh div 2;
      haveSpawn := True;
    end;
  end;

  function Split(x, y, lw, lh, depth: LongInt): LongInt;
  var
    a, b, cut: LongInt;
    splitVert: Boolean;
  begin
    if (depth >= gp.MaxDepth) or
       ((lw < 2 * gp.MinLeaf) and (lh < 2 * gp.MinLeaf)) then begin
      Split := CarveRoom(x, y, lw, lh);
      exit;
    end;
    if lw > lh then splitVert := True
    else if lh > lw then splitVert := False
    else splitVert := RngBelow(r, 2) = 0;

    if splitVert and (lw >= 2 * gp.MinLeaf) then begin
      cut := RngRange(r, gp.MinLeaf, lw - gp.MinLeaf);
      a := Split(x, y, cut, lh, depth + 1);
      b := Split(x + cut, y, lw - cut, lh, depth + 1);
      Corridor(a, b);
      Split := a;
    end
    else if lh >= 2 * gp.MinLeaf then begin
      cut := RngRange(r, gp.MinLeaf, lh - gp.MinLeaf);
      a := Split(x, y, lw, cut, depth + 1);
      b := Split(x, y + cut, lw, lh - cut, depth + 1);
      Corridor(a, b);
      Split := a;
    end
    else
      Split := CarveRoom(x, y, lw, lh);
  end;

var
  i: LongInt;
begin
  for i := 0 to cw * ch - 1 do cells[i] := TILE_ROCK;
  RoomGraphInit(gph);
  haveSpawn := False;
  sx := cw div 2; sy := ch div 2;
  Split(0, 0, cw, ch, 0);
  spawnX := sx; spawnY := sy;
end;

const
  { The dungeon's boundary dressing, applied in order after carving. The wall ring
    runs over the whole buffer (margin 0); the doorway needs its flanking cells in
    range, so it keeps off the outermost ring (margin 1). }
  DUNGEON_DRESS: array[0..1] of TGenRule = (
    (Match: @SockWallRing;     Becomes: TILE_WALL; Margin: 0),
    (Match: @SockDoorCrossing; Becomes: TILE_DOOR; Margin: 1)
  );

procedure DressDungeon(var cells: array of Byte; cw, ch: LongInt);
begin
  GenApplySockets(cells, cw, ch, DUNGEON_DRESS);
end;

procedure GenerateDungeon(out m: TTileMap; out gph: TRoomGraph;
  w, h: LongInt; seed: QWord);
var
  r: TRng;
begin
  TileMapInit(m, w, h);
  RngSeed(r, seed);
  CarveRooms(m.Cells, w, h, r, gph, m.SpawnX, m.SpawnY, DefaultGenParams);
  DressDungeon(m.Cells, w, h);
end;

end.
