program t_prop;

{** Tests the prop-brush path: a prop cell (a forest tree) blocks movement but shows no
  wall face, carries a floor under it, and emits a centred prop instance rather than wall
  panels on its neighbours. Exercised against the hamlet's surrounding forest, where trees
  are placed as TILE_PROP cells. GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld, tilesock, brushdef, brushfield;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  tw: TTileWorld;
  tx, ty, px, py, i, dir: LongInt;
  foundProp, emitted, facedWall: Boolean;
  list: TBrushList;
  dx: array[0..3] of LongInt = (0, -1, 0, 1);
  dy: array[0..3] of LongInt = (-1, 0, 1, 0);
begin
  fails := 0;

  { The town world: region (0,0) is the hamlet; the regions around it are forest with
    scattered tree props. Scan a forest region for the first prop cell. }
  TileWorldInitTown(tw, 4242);
  foundProp := False;
  px := 0; py := 0;
  for ty := 0 to REGION - 1 do
    for tx := REGION to 2 * REGION - 1 do
      if (not foundProp) and (TileAt(tw, tx, ty) = TILE_PROP) then begin
        foundProp := True; px := tx; py := ty;
      end;
  Check(foundProp, 'the forest holds a prop cell');

  if foundProp then begin
    { A tree blocks the body but is not a wall: non-walkable, yet not solid, so no wall
      panel grows against it and the floor still lays under it. }
    Check(not TileWorldWalkable(tw, px, py), 'a prop cell blocks movement');
    Check(not TileWorldSolid(tw, px, py), 'a prop cell presents no wall face');
    Check(SocketCell(skPropCell, tw, px, py), 'the prop cell matches the prop socket');
    Check(SocketCell(skOpenCell, tw, px, py), 'the prop cell still carries a floor');

    { No open neighbour grows a wall panel facing the tree. }
    facedWall := False;
    for dir := 0 to 3 do
      if (not TileWorldSolid(tw, px + dx[dir], py + dy[dir])) and
         SocketEdge(skWallEdge, tw, px + dx[dir], py + dy[dir], -dx[dir], -dy[dir]) then
        facedWall := True;
    Check(not facedWall, 'no wall panel faces the tree');

    { The region's emitted list carries a centred prop instance at the tree. }
    BrushEmitRegion(tw, 1, 0, list);
    emitted := False;
    for i := 0 to list.N - 1 do
      if (DUNGEON_BRUSHES[list.Inst[i].Brush].Style = stProp) and
         (list.Inst[i].X = px) and (list.Inst[i].Y = py) then emitted := True;
    Check(emitted, 'the art field emits a prop instance at the tree');
  end;

  TileWorldFree(tw);

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
