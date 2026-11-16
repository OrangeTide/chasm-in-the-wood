program t_worldgraph;

{** Tests the stitched world portal graph: a room reaches itself at distance zero,
  the seam links are bidirectional, and rooms in different zones are connected, so the
  separately generated regions and zones form one seamless space. All GL-free. }

{$mode objfpc}{$H+}

uses
  tileworld, themes, worldgraph;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function FindRoomInRegion(var tw: TTileWorld; rx, ry: LongInt;
  out ref: TRoomRef): Boolean;
{ Any room inside region (rx, ry). }
var
  tx, ty: LongInt;
begin
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do
      if TileWorldRoomAt(tw, rx * REGION + tx, ry * REGION + ty, ref) then begin
        FindRoomInRegion := True;
        exit;
      end;
  FindRoomInRegion := False;
end;

function Lists(var tw: TTileWorld; const a, b: TRoomRef): Boolean;
{ Whether b appears among a's neighbours. }
var
  nbrs: array[0..31] of TRoomRef;
  n, i: LongInt;
begin
  TileWorldRoomNeighbours(tw, a, nbrs, n);
  for i := 0 to n - 1 do
    if (nbrs[i].rx = b.rx) and (nbrs[i].ry = b.ry) and (nbrs[i].idx = b.idx) then begin
      Lists := True;
      exit;
    end;
  Lists := False;
end;

var
  tw: TTileWorld;
  a, b: TRoomRef;
  nbrs: array[0..31] of TRoomRef;
  n, i, originTheme, farRx, d: LongInt;
begin
  fails := 0;
  TileWorldInit(tw, 1337, 0);

  { A room in the origin region. }
  Check(FindRoomInRegion(tw, 0, 0, a), 'no room in the origin region');

  { A room reaches itself at distance zero. }
  Check(WorldGraphDistance(tw, a, a, 1000) = 0, 'a room is not at distance 0 from itself');

  { The seam and portal links are bidirectional. }
  TileWorldRoomNeighbours(tw, a, nbrs, n);
  Check(n > 0, 'the origin room has no neighbours');
  for i := 0 to n - 1 do
    Check(Lists(tw, nbrs[i], a), 'a neighbour does not link back');

  { Pick a region several zones away and confirm its rooms connect to the origin,
    across every zone boundary in between: the zones are stitched into one space. }
  originTheme := TileWorldThemeAt(tw, 0, 0);
  farRx := ZONE_REGIONS * 3 + 1;   { three zone-blocks out }
  Check(farRx div ZONE_REGIONS <> 0, 'far region is in the origin zone');
  Check(FindRoomInRegion(tw, farRx, 0, b), 'no room in the far region');

  d := WorldGraphDistance(tw, a, b, 8000);
  Check(d > 0, 'a room several zones away is not reachable from the origin');
  Check(WorldGraphDistance(tw, b, a, 8000) = d, 'portal distance is not symmetric');

  writeln('  origin zone theme ', originTheme, ', far region (', farRx,
          ',0) in zone (', farRx div ZONE_REGIONS, ',0); ', d, ' portals apart');
  TileWorldFree(tw);
  if fails = 0 then writeln('  ok') else halt(1);
end.
