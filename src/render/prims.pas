unit prims;

{** Procedurally generated placeholder voxel models.

  The authored art is being replaced, so until it lands the world is drawn from simple
  shapes built by formula here, not by hand: a ball for every free-standing thing (the
  player, monsters, loot), a rectangular plate for a wall, an arch for a door, and a
  short flight of steps for stairs. Each is a plain white voxel model (the draw tint
  colours it) in the file's z-up orientation, so it feeds the same mesher and transforms
  as a loaded model would.

  Nothing here hand-places voxels for a recognizable object; each shape is a closed-form
  fill over the grid, so the result scales with the requested size. }

{$mode objfpc}{$H+}

interface

uses
  voxfile;

{ A solid ball of the given diameter in voxels. }
procedure PrimSphere(out m: TVoxModel; diam: LongInt);

{ A solid rectangular block, sx by sy by sz voxels (z up). }
procedure PrimPlate(out m: TVoxModel; sx, sy, sz: LongInt);

{ A wall plate of sx by sy by sz with an arched opening punched through both horizontal
  directions, so it reads as a doorway from any side and can be walked through. }
procedure PrimArch(out m: TVoxModel; sx, sy, sz: LongInt);

{ A flight of steps rising along +x, filling an sx by sy by sz box in nsteps treads. }
procedure PrimSteps(out m: TVoxModel; sx, sy, sz, nsteps: LongInt);

implementation

procedure White(var m: TVoxModel);
begin
  m.Palette[1].R := 255;
  m.Palette[1].G := 255;
  m.Palette[1].B := 255;
  m.Palette[1].A := 255;
end;

procedure PrimSphere(out m: TVoxModel; diam: LongInt);
var
  x, y, z: LongInt;
  c, rr, dx, dy, dz: Single;
begin
  if diam < 1 then diam := 1;
  VoxAlloc(m, diam, diam, diam);
  White(m);
  c := (diam - 1) / 2.0;
  rr := (diam / 2.0) * (diam / 2.0);
  for z := 0 to diam - 1 do
    for y := 0 to diam - 1 do
      for x := 0 to diam - 1 do begin
        dx := x - c; dy := y - c; dz := z - c;
        if dx * dx + dy * dy + dz * dz <= rr then VoxSetCell(m, x, y, z, 1);
      end;
end;

procedure PrimPlate(out m: TVoxModel; sx, sy, sz: LongInt);
var
  x, y, z: LongInt;
begin
  if sx < 1 then sx := 1;
  if sy < 1 then sy := 1;
  if sz < 1 then sz := 1;
  VoxAlloc(m, sx, sy, sz);
  White(m);
  for z := 0 to sz - 1 do
    for y := 0 to sy - 1 do
      for x := 0 to sx - 1 do VoxSetCell(m, x, y, z, 1);
end;

procedure PrimArch(out m: TVoxModel; sx, sy, sz: LongInt);
var
  x, y, z: LongInt;
  jamb, lintel: LongInt;
  cu, cv, openX, openY, apex, du, dv, archU, archV: Single;
  carve: Boolean;
begin
  if sx < 3 then sx := 3;
  if sy < 3 then sy := 3;
  if sz < 3 then sz := 3;
  VoxAlloc(m, sx, sy, sz);
  White(m);
  jamb := sx div 5; if jamb < 1 then jamb := 1;
  lintel := sz div 4; if lintel < 1 then lintel := 1;
  cu := (sx - 1) / 2.0;
  cv := (sy - 1) / 2.0;
  openX := sx / 2.0 - jamb;      { half-width of the opening across x }
  openY := sy / 2.0 - jamb;      { half-width of the opening across y }
  apex := sz - lintel;           { height the arch rises to before the lintel }
  if openX < 1 then openX := 1;
  if openY < 1 then openY := 1;
  for z := 0 to sz - 1 do
    for y := 0 to sy - 1 do
      for x := 0 to sx - 1 do begin
        { Start solid, then carve the two arched tunnels out of the plate. }
        carve := False;
        du := Abs(x - cu);
        if du <= openX then begin
          archU := apex * Sqrt(1 - (du / openX) * (du / openX));
          if z <= archU then carve := True;   { tunnel open along y }
        end;
        dv := Abs(y - cv);
        if dv <= openY then begin
          archV := apex * Sqrt(1 - (dv / openY) * (dv / openY));
          if z <= archV then carve := True;   { tunnel open along x }
        end;
        if not carve then VoxSetCell(m, x, y, z, 1);
      end;
end;

procedure PrimSteps(out m: TVoxModel; sx, sy, sz, nsteps: LongInt);
var
  i, x, y, z, x0, x1, h: LongInt;
begin
  if sx < 1 then sx := 1;
  if sy < 1 then sy := 1;
  if sz < 1 then sz := 1;
  if nsteps < 1 then nsteps := 1;
  VoxAlloc(m, sx, sy, sz);
  White(m);
  for i := 0 to nsteps - 1 do begin
    x0 := (i * sx) div nsteps;
    x1 := ((i + 1) * sx) div nsteps - 1;
    h := ((i + 1) * sz) div nsteps;
    for z := 0 to h - 1 do
      for y := 0 to sy - 1 do
        for x := x0 to x1 do VoxSetCell(m, x, y, z, 1);
  end;
end;

end.
