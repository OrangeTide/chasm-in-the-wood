program t_brushfield;

{** Tests the art field: the generator's tiles emitted as brush instances.

  The emission must agree with the socket registry it is built from. Every instance
  is checked against the socket that should justify it, and the per style counts are
  recomputed by an independent sweep of the region and compared. Emission must also
  be deterministic: the same region emits the identical list. GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld, brushdef, brushfield;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function ListsEqual(const a, b: TBrushList): Boolean;
var
  i: LongInt;
begin
  ListsEqual := False;
  if a.N <> b.N then exit;
  for i := 0 to a.N - 1 do
    if (a.Inst[i].Brush <> b.Inst[i].Brush) or (a.Inst[i].X <> b.Inst[i].X) or
       (a.Inst[i].Y <> b.Inst[i].Y) or (a.Inst[i].Rot <> b.Inst[i].Rot) then exit;
  ListsEqual := True;
end;

function DoorAlongZ(var tw: TTileWorld; tx, ty: LongInt): Boolean;
begin
  DoorAlongZ := TileWorldSolid(tw, tx, ty - 1) and TileWorldSolid(tw, tx, ty + 1);
end;

var
  tw: TTileWorld;
  la, lb: TBrushList;
  k, tx, ty, dir, i: LongInt;
  d: TBrushDesc;
  justified: Boolean;
  { per style tallies from the emitted list }
  eFloor, eWall, ePost, eGate, eDoor, eUp, eDn, eProp: LongInt;
  { per style tallies from an independent sweep }
  cFloor, cWall, cPost, cGate, cDoor, cUp, cDn, cProp: LongInt;
begin
  fails := 0;

  TileWorldInit(tw, 7, 1);

  BrushEmitRegion(tw, 0, 0, la);
  BrushEmitRegion(tw, 0, 0, lb);
  Check(la.N > 0, 'region emitted no instances');
  Check(ListsEqual(la, lb), 'emission is not deterministic');

  { Every instance is justified by its socket, and sits inside region (0,0). }
  eFloor := 0; eWall := 0; ePost := 0; eGate := 0; eDoor := 0; eUp := 0; eDn := 0;
  eProp := 0;
  for k := 0 to la.N - 1 do begin
    d := DUNGEON_BRUSHES[la.Inst[k].Brush];
    tx := la.Inst[k].X; ty := la.Inst[k].Y;
    Check((tx >= 0) and (tx < REGION) and (ty >= 0) and (ty < REGION),
          'instance outside its region');
    justified := False;
    case d.Anchor of
      baCell:   justified := SocketCell(d.Socket, tw, tx, ty);
      baEdge:   justified := SocketEdge(d.Socket, tw, tx, ty,
                               EDGE_DX[la.Inst[k].Rot], EDGE_DY[la.Inst[k].Rot]);
      baCorner: justified := SocketCorner(d.Socket, tw, tx, ty);
    end;
    Check(justified, 'an emitted instance is not justified by its socket');
    case d.Style of
      stFloorPlate: Inc(eFloor);
      stEdgePanel:  Inc(eWall);
      stCornerPost: Inc(ePost);
      stGate:       begin Inc(eGate);
                      Check((la.Inst[k].Rot = 1) = DoorAlongZ(tw, tx, ty),
                            'gate orientation does not match its wall'); end;
      stDoorSwing:  begin Inc(eDoor);
                      Check((la.Inst[k].Rot = 1) = DoorAlongZ(tw, tx, ty),
                            'door orientation does not match its wall'); end;
      stStairUp:    Inc(eUp);
      stStairDn:    Inc(eDn);
      stProp:       Inc(eProp);
    end;
  end;

  { Independent sweep: count what each socket matches across the region, the same
    totals emission should have produced, by a different loop. }
  cFloor := 0; cWall := 0; cPost := 0; cGate := 0; cDoor := 0; cUp := 0; cDn := 0;
  cProp := 0;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do begin
      if not TileWorldSolid(tw, tx, ty) then begin
        if SocketCell(skOpenCell, tw, tx, ty)    then Inc(cFloor);
        if SocketCell(skGateCell, tw, tx, ty)    then Inc(cGate);
        if SocketCell(skDoorCell, tw, tx, ty)    then Inc(cDoor);
        if SocketCell(skStairUpCell, tw, tx, ty) then Inc(cUp);
        if SocketCell(skStairDnCell, tw, tx, ty) then Inc(cDn);
        if SocketCell(skPropCell, tw, tx, ty)    then Inc(cProp);
        for dir := 0 to 3 do
          if SocketEdge(skWallEdge, tw, tx, ty, EDGE_DX[dir], EDGE_DY[dir]) then Inc(cWall);
      end;
      if SocketCorner(skPostCorner, tw, tx, ty) then Inc(cPost);
    end;

  Check(eProp = cProp, 'prop instance count disagrees with the sweep');
  Check(eFloor = cFloor, 'floor instance count disagrees with the sweep');
  Check(eWall  = cWall,  'wall instance count disagrees with the sweep');
  Check(ePost  = cPost,  'post instance count disagrees with the sweep');
  Check(eGate  = cGate,  'gate instance count disagrees with the sweep');
  Check(eDoor  = cDoor,  'door instance count disagrees with the sweep');
  Check(eUp    = cUp,    'up-stair instance count disagrees with the sweep');
  Check(eDn    = cDn,    'down-stair instance count disagrees with the sweep');

  writeln('  ', la.N, ' instances: ', eFloor, ' floor, ', eWall, ' wall, ',
          ePost, ' post, ', eGate, ' gate, ', eDoor, ' door, ', eUp + eDn, ' stair');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' checks failed'); Halt(1); end;
end.
