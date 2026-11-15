unit frustum;

{** View-frustum culling.

  Extracts the six clip planes from a combined projection*view matrix
  (Gribb-Hartmann) and tests axis-aligned boxes against them. The world uses this
  to skip chunks the camera cannot see, which is the right culler for the elevated
  diorama view: the player sees over low walls, so a plain frustum test is correct
  where strict room-portal culling would wrongly hide visible rooms. }

{$mode objfpc}{$H+}

interface

uses
  vecmath;

type
  TPlane = record
    a, b, c, d: single;
  end;
  TFrustum = array[0..5] of TPlane;

procedure FrustumFromClip(const clip: TMat4; out f: TFrustum);
function FrustumTestAABB(const f: TFrustum; const mn, mx: TVec3): boolean;

implementation

uses
  math;

procedure Normalize(var p: TPlane);
var
  len: single;
begin
  len := sqrt(p.a * p.a + p.b * p.b + p.c * p.c);
  if len > 1e-8 then begin
    p.a := p.a / len; p.b := p.b / len;
    p.c := p.c / len; p.d := p.d / len;
  end;
end;

procedure FrustumFromClip(const clip: TMat4; out f: TFrustum);
{ clip is column-major (element [col*4+row]); its rows are the vectors below. }
var
  r0, r1, r2, r3: array[0..3] of single;
  i: longint;
begin
  for i := 0 to 3 do begin
    r0[i] := clip[i * 4 + 0];
    r1[i] := clip[i * 4 + 1];
    r2[i] := clip[i * 4 + 2];
    r3[i] := clip[i * 4 + 3];
  end;

  { left = r3+r0, right = r3-r0, bottom = r3+r1, top = r3-r1,
    near = r3+r2, far = r3-r2 }
  f[0].a := r3[0] + r0[0]; f[0].b := r3[1] + r0[1]; f[0].c := r3[2] + r0[2]; f[0].d := r3[3] + r0[3];
  f[1].a := r3[0] - r0[0]; f[1].b := r3[1] - r0[1]; f[1].c := r3[2] - r0[2]; f[1].d := r3[3] - r0[3];
  f[2].a := r3[0] + r1[0]; f[2].b := r3[1] + r1[1]; f[2].c := r3[2] + r1[2]; f[2].d := r3[3] + r1[3];
  f[3].a := r3[0] - r1[0]; f[3].b := r3[1] - r1[1]; f[3].c := r3[2] - r1[2]; f[3].d := r3[3] - r1[3];
  f[4].a := r3[0] + r2[0]; f[4].b := r3[1] + r2[1]; f[4].c := r3[2] + r2[2]; f[4].d := r3[3] + r2[3];
  f[5].a := r3[0] - r2[0]; f[5].b := r3[1] - r2[1]; f[5].c := r3[2] - r2[2]; f[5].d := r3[3] - r2[3];

  for i := 0 to 5 do Normalize(f[i]);
end;

function FrustumTestAABB(const f: TFrustum; const mn, mx: TVec3): boolean;
{ False only when the box is fully outside a plane (uses the positive vertex). }
var
  i: longint;
  px, py, pz: single;
begin
  FrustumTestAABB := false;
  for i := 0 to 5 do begin
    if f[i].a >= 0 then px := mx.x else px := mn.x;
    if f[i].b >= 0 then py := mx.y else py := mn.y;
    if f[i].c >= 0 then pz := mx.z else pz := mn.z;
    if f[i].a * px + f[i].b * py + f[i].c * pz + f[i].d < 0 then
      exit;   { box is entirely on the outside of this plane }
  end;
  FrustumTestAABB := true;
end;

end.
