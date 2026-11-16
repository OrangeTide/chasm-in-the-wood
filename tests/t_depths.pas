program t_depths;

{** Tests depths and stairs: the origin always has a down-stair (and an up-stair
  below the top depth), stairs scatter into other regions, a down-stair on one depth
  is matched by an up-stair in the same region one depth down, and different depths
  are different dungeons. All GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  d0, d1, d1b, d2, dn: TTileWorld;
  dx, dy, ux, uy, tx, ty, diffs, rx, ry: LongInt;
  scattered, linked, px, py, qx, qy, bottomDowns: LongInt;
  found: Boolean;
begin
  fails := 0;

  { Depth 1 origin: a down-stair and an up-stair, walkable, at distinct tiles. }
  TileWorldInit(d1, 7, 1);
  Check(TileWorldRegionDownStair(d1, 0, 0, dx, dy), 'origin missing a down-stair');
  Check(TileAt(d1, dx, dy) = TILE_STAIRS_DOWN, 'down-stair tile missing');
  Check(TileWorldWalkable(d1, dx, dy), 'down-stair not walkable');
  Check(TileWorldRegionUpStair(d1, 0, 0, ux, uy), 'origin missing an up-stair at depth 1');
  Check(TileAt(d1, ux, uy) = TILE_STAIRS_UP, 'up-stair tile missing at depth 1');
  Check(TileWorldWalkable(d1, ux, uy), 'up-stair not walkable');
  Check((ux <> dx) or (uy <> dy), 'up-stair and down-stair at the same tile');

  { Depth 0 (the top) has an origin down-stair, and an up-stair that climbs back to the
    surface hamlet, at a distinct tile. }
  TileWorldInit(d0, 7, 0);
  Check(TileWorldRegionDownStair(d0, 0, 0, dx, dy), 'top depth missing a down-stair');
  Check(TileWorldRegionUpStair(d0, 0, 0, ux, uy), 'top depth missing a surface up-stair');
  Check(TileAt(d0, ux, uy) = TILE_STAIRS_UP, 'top up-stair tile missing');
  Check((ux <> dx) or (uy <> dy), 'top up-stair and down-stair at the same tile');

  { Scattering: some region beyond the origin hosts a down-stair. For each such
    region, the next depth's same region has a matching up-stair (the descent lands
    on it). }
  scattered := 0;
  linked := 0;
  for ry := -3 to 3 do
    for rx := -3 to 3 do
      if not ((rx = 0) and (ry = 0)) then
        if TileWorldRegionDownStair(d1, rx, ry, px, py) then begin
          Inc(scattered);
          TileWorldInit(dn, 7, 2);
          found := TileWorldRegionUpStair(dn, rx, ry, qx, qy);
          if found and (TileAt(dn, qx, qy) = TILE_STAIRS_UP) and
             TileWorldWalkable(dn, qx, qy) then Inc(linked);
          TileWorldFree(dn);
        end;
  Check(scattered > 0, 'no stairs scattered beyond the origin');
  Check(linked = scattered, 'a scattered down-stair has no matching up-stair below');

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

  { The deepest depth is the bottom of the chasm: no down-stairs anywhere, so the
    descent ends, but the origin still has an up-stair to climb back. }
  TileWorldInit(dn, 7, DUNGEON_BOTTOM);
  Check(not TileWorldRegionDownStair(dn, 0, 0, dx, dy),
        'the bottom origin still has a down-stair');
  Check(TileWorldRegionUpStair(dn, 0, 0, ux, uy),
        'the bottom origin has no up-stair to climb back');
  bottomDowns := 0;
  for ry := -3 to 3 do
    for rx := -3 to 3 do
      if TileWorldRegionDownStair(dn, rx, ry, px, py) then Inc(bottomDowns);
  Check(bottomDowns = 0, 'the bottom scatters down-stairs past the end');
  TileWorldFree(dn);

  writeln('  ', scattered, ' scattered down-stairs across 48 regions, all linked');
  TileWorldFree(d0);
  TileWorldFree(d1);
  TileWorldFree(d1b);
  TileWorldFree(d2);

  if fails = 0 then writeln('  ok') else halt(1);
end.
