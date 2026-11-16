program t_themes;

{** Tests the zone/theme layer: theme assignment is deterministic and in range,
  a whole zone shares one theme, themes vary across zones and across depths, and
  the tile world reports the same theme for every tile of a region. All GL-free. }

{$mode objfpc}{$H+}

uses
  themes, tileworld;

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  tw, tw2: TTileWorld;
  rx, ry, zx, zy, dx, dy, idx, zoneTheme, seen: longint;
  distinct: array[0..NUM_THEMES - 1] of boolean;
  tx, ty, base, t: longint;
begin
  fails := 0;

  { In range and deterministic for the same seed and coordinates. }
  for ry := -4 to 4 do
    for rx := -4 to 4 do begin
      idx := ThemeIndex(1337, rx, ry);
      Check((idx >= 0) and (idx < NUM_THEMES), 'theme index out of range');
      Check(idx = ThemeIndex(1337, rx, ry), 'theme index not deterministic');
    end;

  { Every region inside a zone shares the zone's theme. }
  for zy := -2 to 2 do
    for zx := -2 to 2 do begin
      zoneTheme := ThemeIndex(1337, zx * ZONE_REGIONS, zy * ZONE_REGIONS);
      for dy := 0 to ZONE_REGIONS - 1 do
        for dx := 0 to ZONE_REGIONS - 1 do
          Check(ThemeIndex(1337, zx * ZONE_REGIONS + dx, zy * ZONE_REGIONS + dy)
                  = zoneTheme, 'a zone holds more than one theme');
    end;

  { Variety: more than one theme appears across a field of zones. }
  for idx := 0 to NUM_THEMES - 1 do distinct[idx] := false;
  for zy := -6 to 6 do
    for zx := -6 to 6 do
      distinct[ThemeIndex(1337, zx * ZONE_REGIONS, zy * ZONE_REGIONS)] := true;
  seen := 0;
  for idx := 0 to NUM_THEMES - 1 do if distinct[idx] then Inc(seen);
  Check(seen >= 2, 'themes do not vary across zones');

  { Depth changes the theme field: folding the depth into the seed must move at
    least one zone's theme between depth 0 and depth 1. }
  TileWorldInit(tw, 1337, 0);
  TileWorldInit(tw2, 1337, 1);
  seen := 0;
  for zy := -6 to 6 do
    for zx := -6 to 6 do begin
      tx := zx * ZONE_REGIONS * REGION;
      ty := zy * ZONE_REGIONS * REGION;
      if TileWorldThemeAt(tw, tx, ty) <> TileWorldThemeAt(tw2, tx, ty) then Inc(seen);
    end;
  Check(seen > 0, 'depth does not change the theme field');
  TileWorldFree(tw);
  TileWorldFree(tw2);

  { The tile world agrees with ThemeIndex, and reports one theme per region. }
  TileWorldInit(tw, 1337, 0);
  for ry := -1 to 1 do
    for rx := -1 to 1 do begin
      base := TileWorldThemeAt(tw, rx * REGION, ry * REGION);
      Check(base = ThemeIndex(tw.seed, rx, ry),
            'tile world theme disagrees with ThemeIndex');
      for ty := 0 to REGION - 1 do
        for tx := 0 to REGION - 1 do begin
          t := TileWorldThemeAt(tw, rx * REGION + tx, ry * REGION + ty);
          Check(t = base, 'a region reports more than one theme');
        end;
    end;
  TileWorldFree(tw);

  writeln('  ', NUM_THEMES, ' themes, zone edge ', ZONE_REGIONS, ' regions, saw ',
          seen, ' distinct across depths');
  if fails = 0 then writeln('  ok') else halt(1);
end.
