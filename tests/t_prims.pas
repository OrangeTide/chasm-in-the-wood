program t_prims;

{** Tests the procedural placeholder shapes: a sphere is a rounded solid smaller than its
  bounding cube, a plate is a full solid block, an arch has an opening carved through it,
  and steps climb from low at one end to full height at the other. GL-free. }

{$mode objfpc}{$H+}

uses
  voxfile, prims;

var
  fails: LongInt;
  m: TVoxModel;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function ColumnHeight(const mm: TVoxModel; x, y: LongInt): LongInt;
{ The highest solid z in a column, plus one, or 0 if the column is empty. }
var
  z: LongInt;
begin
  ColumnHeight := 0;
  for z := mm.Sz - 1 downto 0 do
    if VoxCell(mm, x, y, z) <> 0 then exit(z + 1);
end;

begin
  fails := 0;

  { Sphere: dimensions match the diameter, the centre is solid, the corners are not,
    and it fills less than the whole cube. }
  PrimSphere(m, 11);
  Check((m.Sx = 11) and (m.Sy = 11) and (m.Sz = 11), 'sphere is diam cubed in extent');
  Check(VoxCell(m, 5, 5, 5) <> 0, 'the sphere centre is solid');
  Check(VoxCell(m, 0, 0, 0) = 0, 'a sphere corner is empty');
  Check((VoxSolidCount(m) > 0) and (VoxSolidCount(m) < 11 * 11 * 11),
        'the sphere is rounded, not the full cube');

  { Plate: a full solid block. }
  PrimPlate(m, 4, 5, 6);
  Check(VoxSolidCount(m) = 4 * 5 * 6, 'the plate is a full solid block');

  { Arch: solid at the base corners (jambs) but open through the middle at the base. }
  PrimArch(m, 16, 16, 24);
  Check(VoxCell(m, 0, 0, 0) <> 0, 'an arch jamb corner is solid');
  Check(VoxCell(m, 8, 8, 0) = 0, 'the arch base is open in the middle');
  Check(VoxSolidCount(m) < 16 * 16 * 24, 'the arch is not a solid block');

  { Steps: the far end climbs higher than the near end. }
  PrimSteps(m, 20, 6, 20, 5);
  Check(ColumnHeight(m, 1, 3) < ColumnHeight(m, 18, 3),
        'the steps rise from the near end to the far end');
  Check(ColumnHeight(m, 18, 3) = 20, 'the top step reaches full height');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
