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
  scattered, linked, px, py, qx, qy: LongInt;
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

  { Depth 0 (the top) has an origin down-stair but no up-stair there. }
  TileWorldInit(d0, 7, 0);
  Check(TileWorldRegionDownStair(d0, 0, 0, dx, dy), 'top depth missing a down-stair');
  Check(not TileWorldRegionUpStair(d0, 0, 0, ux, uy), 'top depth has an up-stair');

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

  writeln('  ', scattered, ' scattered down-stairs across 48 regions, all linked');
  TileWorldFree(d0);
  TileWorldFree(d1);
  TileWorldFree(d1b);
  TileWorldFree(d2);

  if fails = 0 then writeln('  ok') else halt(1);
end.
