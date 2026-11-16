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
    A, B, C, D: Single;
  end;
  TFrustum = array[0..5] of TPlane;

procedure FrustumFromClip(const clip: TMat4; out f: TFrustum);
function FrustumTestAABB(const f: TFrustum; const mn, mx: TVec3): Boolean;

implementation

uses
  math;

procedure Normalize(var p: TPlane);
var
  len: Single;
begin
  len := sqrt(p.A * p.A + p.B * p.B + p.C * p.C);
  if len > 1e-8 then begin
    p.A := p.A / len; p.B := p.B / len;
    p.C := p.C / len; p.D := p.D / len;
  end;
end;

procedure FrustumFromClip(const clip: TMat4; out f: TFrustum);
{ clip is column-major (element [col*4+row]); its rows are the vectors below. }
var
  r0, r1, r2, r3: array[0..3] of Single;
  i: LongInt;
begin
  for i := 0 to 3 do begin
    r0[i] := clip[i * 4 + 0];
    r1[i] := clip[i * 4 + 1];
    r2[i] := clip[i * 4 + 2];
    r3[i] := clip[i * 4 + 3];
  end;

  { left = r3+r0, right = r3-r0, bottom = r3+r1, top = r3-r1,
    near = r3+r2, far = r3-r2 }
  f[0].A := r3[0] + r0[0]; f[0].B := r3[1] + r0[1]; f[0].C := r3[2] + r0[2]; f[0].D := r3[3] + r0[3];
  f[1].A := r3[0] - r0[0]; f[1].B := r3[1] - r0[1]; f[1].C := r3[2] - r0[2]; f[1].D := r3[3] - r0[3];
  f[2].A := r3[0] + r1[0]; f[2].B := r3[1] + r1[1]; f[2].C := r3[2] + r1[2]; f[2].D := r3[3] + r1[3];
  f[3].A := r3[0] - r1[0]; f[3].B := r3[1] - r1[1]; f[3].C := r3[2] - r1[2]; f[3].D := r3[3] - r1[3];
  f[4].A := r3[0] + r2[0]; f[4].B := r3[1] + r2[1]; f[4].C := r3[2] + r2[2]; f[4].D := r3[3] + r2[3];
  f[5].A := r3[0] - r2[0]; f[5].B := r3[1] - r2[1]; f[5].C := r3[2] - r2[2]; f[5].D := r3[3] - r2[3];

  for i := 0 to 5 do Normalize(f[i]);
end;

function FrustumTestAABB(const f: TFrustum; const mn, mx: TVec3): Boolean;
{ False only when the box is fully outside a plane (uses the positive vertex). }
var
  i: LongInt;
  px, py, pz: Single;
begin
  FrustumTestAABB := False;
  for i := 0 to 5 do begin
    if f[i].A >= 0 then px := mx.X else px := mn.X;
    if f[i].B >= 0 then py := mx.Y else py := mn.Y;
    if f[i].C >= 0 then pz := mx.Z else pz := mn.Z;
    if f[i].A * px + f[i].B * py + f[i].C * pz + f[i].D < 0 then
      exit;   { box is entirely on the outside of this plane }
  end;
  FrustumTestAABB := True;
end;

end.
