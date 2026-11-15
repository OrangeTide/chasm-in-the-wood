program t_tileworld;

{** Tests the unbounded tile world: deterministic generation, seamless region
  seams, and a walkable spawn. All GL-free. }

{$mode objfpc}{$H+}

uses
  tileworld;

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function VerticalCrossing(var tw: TTileWorld; bx, y0: longint): boolean;
{ A walkable pair straddling the vertical boundary at world x = bx, over one
  region's worth of rows. }
var
  ty: longint;
begin
  VerticalCrossing := false;
  for ty := y0 to y0 + REGION - 1 do
    if TileWorldWalkable(tw, bx - 1, ty) and TileWorldWalkable(tw, bx, ty) then begin
      VerticalCrossing := true; exit;
    end;
end;

function HorizontalCrossing(var tw: TTileWorld; by, x0: longint): boolean;
var
  tx: longint;
begin
  HorizontalCrossing := false;
  for tx := x0 to x0 + REGION - 1 do
    if TileWorldWalkable(tw, tx, by - 1) and TileWorldWalkable(tw, tx, by) then begin
      HorizontalCrossing := true; exit;
    end;
end;

var
  a, b: TTileWorld;
  tx, ty, sx, sy, diffs: longint;
begin
  fails := 0;

  { Determinism: two worlds with the same seed agree everywhere, across several
    regions and into negative coordinates. }
  TileWorldInit(a, 42);
  TileWorldInit(b, 42);
  diffs := 0;
  for ty := -REGION to 2 * REGION - 1 do
    for tx := -REGION to 2 * REGION - 1 do
      if TileAt(a, tx, ty) <> TileAt(b, tx, ty) then Inc(diffs);
  Check(diffs = 0, 'same seed produced different tiles');

  { Seamless seams: a crossing exists on each tested shared edge, including a
    negative-coordinate edge. }
  Check(VerticalCrossing(a, REGION, 0), 'no crossing between region (0,0) and (1,0)');
  Check(VerticalCrossing(a, 2 * REGION, 0), 'no crossing between (1,0) and (2,0)');
  Check(VerticalCrossing(a, 0, 0), 'no crossing between (-1,0) and (0,0)');
  Check(HorizontalCrossing(a, REGION, 0), 'no crossing between (0,0) and (0,1)');
  Check(HorizontalCrossing(a, 0, 0), 'no crossing between (0,-1) and (0,0)');

  { Spawn is walkable. }
  TileWorldSpawn(a, sx, sy);
  Check(TileWorldWalkable(a, sx, sy), 'spawn tile is not walkable');

  writeln('  spawn (', sx, ',', sy, '), ', TileWorldRegionCount(a),
          ' regions generated');
  TileWorldFree(a);
  TileWorldFree(b);
  if fails = 0 then writeln('  ok') else halt(1);
end.
