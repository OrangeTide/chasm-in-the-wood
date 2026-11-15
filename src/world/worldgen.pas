unit worldgen;

{** Hierarchical dungeon generation.

  A binary space partition splits the region into leaves, each leaf gets a room,
  and sibling subtrees are joined by corridors as the recursion unwinds. Rooms and
  corridors are carved as floor, then a one-tile wall ring is laid around the
  carved space. This is the bottom of the generation hierarchy (region -> rooms);
  zone and theme layers come later.

  Alongside the tile map the generator records a room/portal graph: a node per room
  and an edge per corridor. The generator is seeded, so a seed reproduces a level. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap, roomgraph;

procedure GenerateDungeon(out m: TTileMap; out gph: TRoomGraph;
  w, h: longint; seed: qword);

implementation

const
  MIN_LEAF = 9;    { stop splitting below this span }
  MIN_ROOM = 4;
  MAX_DEPTH = 5;
  MARGIN = 1;      { keep rooms off the leaf edge, leaving room for walls }

procedure GenerateDungeon(out m: TTileMap; out gph: TRoomGraph;
  w, h: longint; seed: qword);
var
  r: TRng;
  haveSpawn: boolean;
  rootRoom: longint;

  procedure CarveRect(x0, y0, x1, y1: longint);
  var
    x, y: longint;
  begin
    for y := y0 to y1 do
      for x := x0 to x1 do
        TileSet(m, x, y, TILE_FLOOR);
  end;

  procedure Corridor(ra, rb: longint);
  { L-shaped corridor between two rooms' centres; records a portal edge. }
  var
    ax, ay, bx, by, x, y: longint;
  begin
    ax := RoomCenterX(gph.rooms[ra]); ay := RoomCenterY(gph.rooms[ra]);
    bx := RoomCenterX(gph.rooms[rb]); by := RoomCenterY(gph.rooms[rb]);
    if ax <= bx then for x := ax to bx do TileSet(m, x, ay, TILE_FLOOR)
    else for x := bx to ax do TileSet(m, x, ay, TILE_FLOOR);
    if ay <= by then for y := ay to by do TileSet(m, bx, y, TILE_FLOOR)
    else for y := by to ay do TileSet(m, bx, y, TILE_FLOOR);
    RoomGraphAddPortal(gph, ra, rb, (ax + bx) div 2, (ay + by) div 2);
  end;

  { Carve a room inside the leaf and return its room-graph index. }
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
      m.spawnX := rx + rw div 2; m.spawnY := ry + rh div 2;
      haveSpawn := true;
    end;
  end;

  { Split a region; return a representative room index for connecting. }
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

  procedure LayWalls;
  { Any rock tile touching a floor tile (8-neighbour) becomes a wall. }
  var
    x, y, dx, dy: longint;
    adjacent: boolean;
  begin
    for y := 0 to m.h - 1 do
      for x := 0 to m.w - 1 do
        if TileGet(m, x, y) = TILE_ROCK then begin
          adjacent := false;
          for dy := -1 to 1 do
            for dx := -1 to 1 do
              if TileGet(m, x + dx, y + dy) = TILE_FLOOR then adjacent := true;
          if adjacent then TileSet(m, x, y, TILE_WALL);
        end;
  end;

begin
  TileMapInit(m, w, h);
  RoomGraphInit(gph);
  RngSeed(r, seed);
  haveSpawn := false;
  rootRoom := Split(0, 0, w, h, 0);
  if rootRoom < 0 then ;   { silence unused-result warning }
  LayWalls;
end;

end.
