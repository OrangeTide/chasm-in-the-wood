unit worldgen;

{** Hierarchical dungeon generation.

  A binary space partition splits the region into leaves, each leaf gets a room,
  and sibling subtrees are joined by corridors as the recursion unwinds. This is
  the bottom of the generation hierarchy (region -> rooms); higher layers that
  place zones and themes come later. Rooms and corridors are carved as floor,
  then a one-tile wall ring is laid around the carved space.

  The generator is seeded, so a seed reproduces a level exactly. }

{$mode objfpc}{$H+}

interface

uses
  rng, tilemap;

procedure GenerateDungeon(out m: TTileMap; w, h: longint; seed: qword);

implementation

const
  MIN_LEAF = 9;    { stop splitting below this span }
  MIN_ROOM = 4;
  MAX_DEPTH = 5;
  MARGIN = 1;      { keep rooms off the leaf edge, leaving room for walls }

procedure GenerateDungeon(out m: TTileMap; w, h: longint; seed: qword);
var
  r: TRng;
  haveSpawn: boolean;
  cx, cy: longint;

  procedure CarveRect(x0, y0, x1, y1: longint);
  var
    x, y: longint;
  begin
    for y := y0 to y1 do
      for x := x0 to x1 do
        TileSet(m, x, y, TILE_FLOOR);
  end;

  procedure Corridor(ax, ay, bx, by: longint);
  var
    x, y: longint;
  begin
    { L-shaped: horizontal leg then vertical leg. }
    if ax <= bx then for x := ax to bx do TileSet(m, x, ay, TILE_FLOOR)
    else for x := bx to ax do TileSet(m, x, ay, TILE_FLOOR);
    if ay <= by then for y := ay to by do TileSet(m, bx, y, TILE_FLOOR)
    else for y := by to ay do TileSet(m, bx, y, TILE_FLOOR);
  end;

  { Carve a room inside the leaf [x,y,w,h] and return its centre in rcx,rcy. }
  procedure CarveRoom(x, y, lw, lh: longint; out rcx, rcy: longint);
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
    rcx := rx + rw div 2;
    rcy := ry + rh div 2;
    if not haveSpawn then begin
      m.spawnX := rcx; m.spawnY := rcy;
      haveSpawn := true;
    end;
  end;

  { Split a region; return a connecting point (a room centre) in pcx,pcy. }
  procedure Split(x, y, lw, lh, depth: longint; out pcx, pcy: longint);
  var
    acx, acy, bcx, bcy, cut: longint;
    splitVert: boolean;
  begin
    if (depth >= MAX_DEPTH) or (lw < 2 * MIN_LEAF) and (lh < 2 * MIN_LEAF) then begin
      CarveRoom(x, y, lw, lh, pcx, pcy);
      exit;
    end;

    { Prefer splitting the longer axis; break ties randomly. }
    if lw > lh then splitVert := true
    else if lh > lw then splitVert := false
    else splitVert := RngBelow(r, 2) = 0;

    if splitVert and (lw >= 2 * MIN_LEAF) then begin
      cut := RngRange(r, MIN_LEAF, lw - MIN_LEAF);
      Split(x, y, cut, lh, depth + 1, acx, acy);
      Split(x + cut, y, lw - cut, lh, depth + 1, bcx, bcy);
      Corridor(acx, acy, bcx, bcy);
    end
    else if lh >= 2 * MIN_LEAF then begin
      cut := RngRange(r, MIN_LEAF, lh - MIN_LEAF);
      Split(x, y, lw, cut, depth + 1, acx, acy);
      Split(x, y + cut, lw, lh - cut, depth + 1, bcx, bcy);
      Corridor(acx, acy, bcx, bcy);
    end
    else begin
      CarveRoom(x, y, lw, lh, pcx, pcy);
      exit;
    end;
    pcx := acx; pcy := acy;
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
  RngSeed(r, seed);
  haveSpawn := false;
  Split(0, 0, w, h, 0, cx, cy);
  LayWalls;
end;

end.
