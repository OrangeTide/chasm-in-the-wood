unit worldgen;

{** Hierarchical dungeon generation.

  A binary space partition splits an area into leaves, each leaf gets a room, and
  sibling subtrees are joined by corridors as the recursion unwinds. Rooms and
  corridors are carved as floor; a separate pass lays a wall ring around the carved
  space. This is the bottom of the generation hierarchy, region down to rooms.

  The carving primitives work on a flat tile buffer so they serve both a single
  bounded level (GenerateDungeon, used by tests) and the per-region generation of
  the streaming tile world, which carves rooms, adds seam connections, then walls.
  The generator is seeded, so a seed reproduces a level. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap, roomgraph;

{ Carve rooms and connecting corridors into a cw*ch rock buffer, recording the
  room/portal graph and the spawn tile (the first room's centre). }
procedure CarveRooms(var cells: array of byte; cw, ch: longint; var r: TRng;
  out gph: TRoomGraph; out spawnX, spawnY: longint);

{ Set every rock tile that touches a floor tile (8-neighbour) to wall. }
procedure LayWalls(var cells: array of byte; cw, ch: longint);

{ Place a door on each floor tile that is a single-tile crossing through a wall, a
  room or area entrance. Long corridors flanked by walls are left plain. }
procedure PlaceDoors(var cells: array of byte; cw, ch: longint);

{ A single bounded level: rock, carve, walls. }
procedure GenerateDungeon(out m: TTileMap; out gph: TRoomGraph;
  w, h: longint; seed: qword);

implementation

const
  MIN_LEAF = 9;
  MIN_ROOM = 4;
  MAX_DEPTH = 5;
  MARGIN = 1;

procedure CarveRooms(var cells: array of byte; cw, ch: longint; var r: TRng;
  out gph: TRoomGraph; out spawnX, spawnY: longint);
var
  haveSpawn: boolean;
  sx, sy: longint;

  procedure SetF(x, y: longint; v: byte);
  begin
    if (x >= 0) and (y >= 0) and (x < cw) and (y < ch) then
      cells[x + y * cw] := v;
  end;

  procedure CarveRect(x0, y0, x1, y1: longint);
  var
    x, y: longint;
  begin
    for y := y0 to y1 do
      for x := x0 to x1 do
        SetF(x, y, TILE_FLOOR);
  end;

  procedure Corridor(ra, rb: longint);
  var
    ax, ay, bx, by, x, y: longint;
  begin
    ax := RoomCenterX(gph.rooms[ra]); ay := RoomCenterY(gph.rooms[ra]);
    bx := RoomCenterX(gph.rooms[rb]); by := RoomCenterY(gph.rooms[rb]);
    if ax <= bx then for x := ax to bx do SetF(x, ay, TILE_FLOOR)
    else for x := bx to ax do SetF(x, ay, TILE_FLOOR);
    if ay <= by then for y := ay to by do SetF(bx, y, TILE_FLOOR)
    else for y := by to ay do SetF(bx, y, TILE_FLOOR);
    RoomGraphAddPortal(gph, ra, rb, (ax + bx) div 2, (ay + by) div 2);
  end;

  function CarveRoom(x, y, lw, lh: longint): longint;
  var
    rw, rh, rx, ry: longint;
  begin
    rw := RngRange(r, MIN_ROOM, lw - 2 * MARGIN);
    rh := RngRange(r, MIN_ROOM, lh - 2 * MARGIN);
    if rw < 1 then rw := 1;
    if rh < 1 then rh := 1;
    rx := x + MARGIN + RngBelow(r, lw - 2 * MARGIN - rw + 1);
    ry := y + MARGIN + RngBelow(r, lh - 2 * MARGIN - rh + 1);
    CarveRect(rx, ry, rx + rw - 1, ry + rh - 1);
    CarveRoom := RoomGraphAddRoom(gph, rx, ry, rw, rh);
    if not haveSpawn then begin
      sx := rx + rw div 2; sy := ry + rh div 2;
      haveSpawn := true;
    end;
  end;

  function Split(x, y, lw, lh, depth: longint): longint;
  var
    a, b, cut: longint;
    splitVert: boolean;
  begin
    if (depth >= MAX_DEPTH) or ((lw < 2 * MIN_LEAF) and (lh < 2 * MIN_LEAF)) then begin
      Split := CarveRoom(x, y, lw, lh);
      exit;
    end;
    if lw > lh then splitVert := true
    else if lh > lw then splitVert := false
    else splitVert := RngBelow(r, 2) = 0;

    if splitVert and (lw >= 2 * MIN_LEAF) then begin
      cut := RngRange(r, MIN_LEAF, lw - MIN_LEAF);
      a := Split(x, y, cut, lh, depth + 1);
      b := Split(x + cut, y, lw - cut, lh, depth + 1);
      Corridor(a, b);
      Split := a;
    end
    else if lh >= 2 * MIN_LEAF then begin
      cut := RngRange(r, MIN_LEAF, lh - MIN_LEAF);
      a := Split(x, y, lw, cut, depth + 1);
      b := Split(x, y + cut, lw, lh - cut, depth + 1);
      Corridor(a, b);
      Split := a;
    end
    else
      Split := CarveRoom(x, y, lw, lh);
  end;

var
  i: longint;
begin
  for i := 0 to cw * ch - 1 do cells[i] := TILE_ROCK;
  RoomGraphInit(gph);
  haveSpawn := false;
  sx := cw div 2; sy := ch div 2;
  Split(0, 0, cw, ch, 0);
  spawnX := sx; spawnY := sy;
end;

procedure LayWalls(var cells: array of byte; cw, ch: longint);

  function GetF(x, y: longint): byte;
  begin
    if (x >= 0) and (y >= 0) and (x < cw) and (y < ch) then GetF := cells[x + y * cw]
    else GetF := TILE_ROCK;
  end;

var
  x, y, dx, dy: longint;
  adjacent: boolean;
begin
  for y := 0 to ch - 1 do
    for x := 0 to cw - 1 do
      if GetF(x, y) = TILE_ROCK then begin
        adjacent := false;
        for dy := -1 to 1 do
          for dx := -1 to 1 do
            if GetF(x + dx, y + dy) = TILE_FLOOR then adjacent := true;
        if adjacent then cells[x + y * cw] := TILE_WALL;
      end;
end;

procedure PlaceDoors(var cells: array of byte; cw, ch: longint);

  function Get(x, y: longint): byte;
  begin
    if (x >= 0) and (y >= 0) and (x < cw) and (y < ch) then Get := cells[x + y * cw]
    else Get := TILE_ROCK;
  end;

  function IsWall(x, y: longint): boolean;
  begin
    IsWall := Get(x, y) = TILE_WALL;
  end;

var
  x, y: longint;
begin
  for y := 1 to ch - 2 do
    for x := 1 to cw - 2 do
      if Get(x, y) = TILE_FLOOR then begin
        { A crossing: walls on two opposite sides, where at least one side along the
          passage opens out of its wall flanking, into a room or a wider space. }
        if IsWall(x - 1, y) and IsWall(x + 1, y) and
           (not (IsWall(x - 1, y - 1) and IsWall(x + 1, y - 1)) or
            not (IsWall(x - 1, y + 1) and IsWall(x + 1, y + 1))) then
          cells[x + y * cw] := TILE_DOOR
        else if IsWall(x, y - 1) and IsWall(x, y + 1) and
           (not (IsWall(x - 1, y - 1) and IsWall(x - 1, y + 1)) or
            not (IsWall(x + 1, y - 1) and IsWall(x + 1, y + 1))) then
          cells[x + y * cw] := TILE_DOOR;
      end;
end;

procedure GenerateDungeon(out m: TTileMap; out gph: TRoomGraph;
  w, h: longint; seed: qword);
var
  r: TRng;
begin
  TileMapInit(m, w, h);
  RngSeed(r, seed);
  CarveRooms(m.cells, w, h, r, gph, m.spawnX, m.spawnY);
  LayWalls(m.cells, w, h);
  PlaceDoors(m.cells, w, h);
end;

end.
