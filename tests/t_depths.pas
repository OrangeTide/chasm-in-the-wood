program t_depths;

{** Tests depths and stairs: each depth has a down-stair, depths below the top have
  an up-stair, the stairs are walkable and distinct, and different depths are
  different dungeons. All GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld;

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  d0, d1, d1b, d2: TTileWorld;
  dx, dy, ux, uy, tx, ty, diffs: longint;
begin
  fails := 0;

  { Depth 1: a down-stair and an up-stair, walkable, at distinct tiles. }
  TileWorldInit(d1, 7, 1);
  TileWorldDownStair(d1, dx, dy);
  Check(TileAt(d1, dx, dy) = TILE_STAIRS_DOWN, 'down-stair tile missing');
  Check(TileWorldWalkable(d1, dx, dy), 'down-stair not walkable');
  TileWorldUpStair(d1, ux, uy);
  Check(TileAt(d1, ux, uy) = TILE_STAIRS_UP, 'up-stair tile missing at depth 1');
  Check(TileWorldWalkable(d1, ux, uy), 'up-stair not walkable');
  Check((ux <> dx) or (uy <> dy), 'up-stair and down-stair at the same tile');

  { Depth 0 (the top) has a down-stair but no up-stair. }
  TileWorldInit(d0, 7, 0);
  TileWorldDownStair(d0, dx, dy);
  Check(TileAt(d0, dx, dy) = TILE_STAIRS_DOWN, 'top depth missing a down-stair');

  { Each depth is a different dungeon. }
  TileWorldInit(d2, 7, 2);
  diffs := 0;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do
      if TileAt(d1, tx, ty) <> TileAt(d2, tx, ty) then Inc(diffs);
  Check(diffs > 0, 'two depths produced the same dungeon');

  { A depth is reproducible. }
  TileWorldInit(d1b, 7, 1);
  diffs := 0;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do
      if TileAt(d1, tx, ty) <> TileAt(d1b, tx, ty) then Inc(diffs);
  Check(diffs = 0, 'same depth not reproducible');

  TileWorldFree(d0);
  TileWorldFree(d1);
  TileWorldFree(d1b);
  TileWorldFree(d2);

  if fails = 0 then writeln('  ok') else halt(1);
end.
