program t_voxemit;

{** Tests emissive materials: a fresh model has no emission, an emissive colour index
  survives a save and load through the MATL chunk, and the mesher carries the emission
  onto the vertices of faces that use that index while leaving ordinary faces at zero.
  GL-free. }

{$mode objfpc}{$H+}

uses
  voxfile, voxmesh;

var
  fails: LongInt;
  m, r: TVoxModel;
  mesh: TVoxMesh;
  i, emitVerts, plainVerts: LongInt;
  path: String;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

begin
  fails := 0;

  { Two voxels in a row: index 1 ordinary, index 2 emissive. }
  VoxAlloc(m, 2, 1, 1);
  Check(m.Emit[1] = 0, 'a fresh model has no emission');
  Check(m.Emit[2] = 0, 'a fresh model has no emission on any index');
  VoxSetCell(m, 0, 0, 0, 1);
  VoxSetCell(m, 1, 0, 0, 2);
  m.Palette[1].R := 200; m.Palette[1].G := 200; m.Palette[1].B := 200;
  m.Palette[1].A := 255;
  m.Palette[2].R := 255; m.Palette[2].G := 180; m.Palette[2].B := 40;
  m.Palette[2].A := 255;
  m.Emit[2] := 0.75;

  { Save and load: the emissive material round-trips through MATL. }
  path := 'build/tests/emit_rt.vox';
  Check(VoxSave(path, m), 'save succeeds');
  Check(VoxLoad(path, r), 'load succeeds');
  Check(r.Emit[1] = 0, 'the ordinary index stays unlit after a round-trip');
  Check(Abs(r.Emit[2] - 0.75) < 0.001, 'the emissive index round-trips its strength');

  { The mesher stamps emission onto the emissive faces and nothing else. }
  BuildMesh(r, mesh);
  Check(mesh.Nverts > 0, 'the mesh has vertices');
  emitVerts := 0;
  plainVerts := 0;
  for i := 0 to mesh.Nverts - 1 do
    if mesh.Verts[i].E > 0 then Inc(emitVerts) else Inc(plainVerts);
  Check(emitVerts > 0, 'some vertices carry emission');
  Check(plainVerts > 0, 'some vertices carry none');
  for i := 0 to mesh.Nverts - 1 do
    if mesh.Verts[i].E > 0 then
      Check(Abs(mesh.Verts[i].E - 0.75) < 0.001, 'emission equals the material strength');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
