program t_tileworld;

{** Tests the unbounded tile world: deterministic generation, seamless region
  seams, and a walkable spawn. All GL-free. }

{$mode objfpc}{$H+}

uses
  tileworld;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function VerticalCrossing(var tw: TTileWorld; bx, y0: LongInt): Boolean;
{ A walkable pair straddling the vertical boundary at world x = bx, over one
  region's worth of rows. }
var
  ty: LongInt;
begin
  VerticalCrossing := False;
  for ty := y0 to y0 + REGION - 1 do
    if TileWorldWalkable(tw, bx - 1, ty) and TileWorldWalkable(tw, bx, ty) then begin
      VerticalCrossing := True; exit;
    end;
end;

function HorizontalCrossing(var tw: TTileWorld; by, x0: LongInt): Boolean;
var
  tx: LongInt;
begin
  HorizontalCrossing := False;
  for tx := x0 to x0 + REGION - 1 do
    if TileWorldWalkable(tw, tx, by - 1) and TileWorldWalkable(tw, tx, by) then begin
      HorizontalCrossing := True; exit;
    end;
end;

var
  a, b, c: TTileWorld;
  tx, ty, sx, sy, diffs, k: LongInt;
  sig: array of Byte;
begin
  fails := 0;

  { Determinism: two worlds with the same seed agree everywhere, across several
    regions and into negative coordinates. }
  TileWorldInit(a, 42, 0);
  TileWorldInit(b, 42, 0);
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

  { LRU eviction: the resident region count stays capped, and an evicted region
    regenerates identically when it is read again. }
  TileWorldInit(c, 99, 0);
  SetLength(sig, REGION * REGION);
  k := 0;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do begin sig[k] := TileAt(c, tx, ty); Inc(k); end;
  for k := 1 to MAX_REGIONS + 20 do
    TileAt(c, k * REGION + 5, k * REGION + 5);   { far reads force eviction }
  Check(TileWorldRegionCount(c) <= MAX_REGIONS, 'resident regions exceed the cap');
  diffs := 0; k := 0;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do begin
      if TileAt(c, tx, ty) <> sig[k] then Inc(diffs);
      Inc(k);
    end;
  Check(diffs = 0, 'an evicted region regenerated differently');

  writeln('  spawn (', sx, ',', sy, '), ', TileWorldRegionCount(a),
          ' regions; cap ', MAX_REGIONS, ', held ', TileWorldRegionCount(c),
          ' after forcing ', MAX_REGIONS + 20);
  TileWorldFree(a);
  TileWorldFree(b);
  TileWorldFree(c);
  if fails = 0 then writeln('  ok') else halt(1);
end.
