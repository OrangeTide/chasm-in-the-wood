program t_tilesock;

{** Tests the shared socket layer that drives generation, rendering, and collision.

  The load bearing check is equivalence: the data driven dressing pass
  (DressDungeon, a socket rule table) must produce byte for byte the same tiles as
  the original hand coded wall and door passes, kept here verbatim as a reference.
  If the refactor ever changes a generated tile, this fails. The rest spot checks
  the socket predicates on small hand built patterns. GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, roomgraph, rng, worldgen, tilesock;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

{ ---- the original dressing passes, verbatim, as a reference ---- }

procedure OldLayWalls(var cells: array of Byte; cw, ch: LongInt);

  function GetF(x, y: LongInt): Byte;
  begin
    if (x >= 0) and (y >= 0) and (x < cw) and (y < ch) then GetF := cells[x + y * cw]
    else GetF := TILE_ROCK;
  end;

var
  x, y, dx, dy: LongInt;
  adjacent: Boolean;
begin
  for y := 0 to ch - 1 do
    for x := 0 to cw - 1 do
      if GetF(x, y) = TILE_ROCK then begin
        adjacent := False;
        for dy := -1 to 1 do
          for dx := -1 to 1 do
            if GetF(x + dx, y + dy) = TILE_FLOOR then adjacent := True;
        if adjacent then cells[x + y * cw] := TILE_WALL;
      end;
end;

procedure OldPlaceDoors(var cells: array of Byte; cw, ch: LongInt);

  function Get(x, y: LongInt): Byte;
  begin
    if (x >= 0) and (y >= 0) and (x < cw) and (y < ch) then Get := cells[x + y * cw]
    else Get := TILE_ROCK;
  end;

  function IsWall(x, y: LongInt): Boolean;
  begin
    IsWall := Get(x, y) = TILE_WALL;
  end;

var
  x, y: LongInt;
begin
  for y := 1 to ch - 2 do
    for x := 1 to cw - 2 do
      if Get(x, y) = TILE_FLOOR then begin
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

{ A carved rock/floor buffer for a seed: rooms and corridors, no walls or doors yet. }
procedure Carve(var cells: array of Byte; w, h: LongInt; seed: QWord);
var
  r: TRng;
  g: TRoomGraph;
  sx, sy: LongInt;
begin
  RngSeed(r, seed);
  CarveRooms(cells, w, h, r, g, sx, sy, DefaultGenParams);
end;

{ ---- a probe over a local buffer, for the predicate spot checks ---- }

var
  gW, gH: LongInt;
  gBuf: array of Byte;

function LocalProbe(ctx: Pointer; x, y: LongInt): Byte;
begin
  if (x >= 0) and (y >= 0) and (x < gW) and (y < gH) then LocalProbe := gBuf[x + y * gW]
  else LocalProbe := TILE_ROCK;
end;

procedure SetCell(x, y: LongInt; v: Byte);
begin
  gBuf[x + y * gW] := v;
end;

const
  W = 48;
  H = 48;

var
  a, b: array of Byte;
  seed, i: LongInt;
  mismatch: LongInt;
begin
  fails := 0;

  { Equivalence across several seeds: the socket driven pass equals the originals. }
  SetLength(a, W * H);
  SetLength(b, W * H);
  mismatch := 0;
  for seed := 1 to 6 do begin
    Carve(a, W, H, 1000 + seed);
    Carve(b, W, H, 1000 + seed);     { same seed, identical carve }
    DressDungeon(a, W, H);           { new: the socket rule table }
    OldLayWalls(b, W, H);            { reference: the original passes }
    OldPlaceDoors(b, W, H);
    for i := 0 to W * H - 1 do
      if a[i] <> b[i] then Inc(mismatch);
  end;
  Check(mismatch = 0, 'socket driven dressing differs from the original passes');

  { Predicate spot checks on a hand built 5x5: a floor cross in a rock field. }
  gW := 5; gH := 5;
  SetLength(gBuf, gW * gH);
  for i := 0 to gW * gH - 1 do gBuf[i] := TILE_ROCK;
  SetCell(2, 1, TILE_FLOOR);
  SetCell(2, 2, TILE_FLOOR);
  SetCell(2, 3, TILE_FLOOR);
  SetCell(1, 2, TILE_FLOOR);
  SetCell(3, 2, TILE_FLOOR);

  { The rock cell at (1,1) touches floor, so the wall ring socket claims it; the
    centre floor does not (it is floor, not rock). }
  Check(SockWallRing(@LocalProbe, nil, 1, 1), 'wall ring on rock touching floor');
  Check(not SockWallRing(@LocalProbe, nil, 2, 2), 'no wall ring on a floor cell');
  Check(not SockWallRing(@LocalProbe, nil, 0, 0), 'no wall ring on rock away from floor');

  { A floor edge facing the rock at (0,2) is a wall edge; facing the floor at (2,2)
    is not. Directions are (dx,dy). }
  Check(SockWallEdge(@LocalProbe, nil, 1, 2, -1, 0), 'wall edge faces solid');
  Check(not SockWallEdge(@LocalProbe, nil, 2, 2, -1, 0), 'no wall edge faces open');

  { Solidity reads rock and wall as solid, floor as open. }
  Check(SockSolid(@LocalProbe, nil, 0, 0), 'rock is solid');
  Check(not SockSolid(@LocalProbe, nil, 2, 2), 'floor is open');

  { A post corner: an L of solid around corner (2,2) turns, so a post belongs; a
    corner inside a straight solid run does not. Build a solid quadrant. }
  for i := 0 to gW * gH - 1 do gBuf[i] := TILE_FLOOR;
  SetCell(0, 0, TILE_WALL);   { NW of corner (1,1) }
  SetCell(1, 0, TILE_WALL);   { NE of corner (1,1): straight top run, no turn }
  Check(not SockPostCorner(@LocalProbe, nil, 1, 1), 'no post on a straight run');
  SetCell(1, 0, TILE_FLOOR);  { leave only NW solid: a lone corner turns }
  Check(SockPostCorner(@LocalProbe, nil, 1, 1), 'post where a wall turns');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' checks failed'); Halt(1); end;
end.
