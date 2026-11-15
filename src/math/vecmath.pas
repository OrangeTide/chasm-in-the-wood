unit vecmath;

{** Small 3D vector and 4x4 matrix helpers for the renderer.

  Matrices are column-major, the layout OpenGL expects, so a TMat4 can be handed
  straight to glUniformMatrix4fv with transpose = GL_FALSE. Element m[c*4 + r] is
  row r, column c. Angles are radians. }

{$mode objfpc}{$H+}

interface

type
  TVec3 = record
    x, y, z: single;
  end;

  { Column-major 4x4. Index as m[col*4 + row]. }
  TMat4 = array[0..15] of single;

function Vec3(x, y, z: single): TVec3;
function Vec3Sub(const a, b: TVec3): TVec3;
function Vec3Cross(const a, b: TVec3): TVec3;
function Vec3Normalize(const a: TVec3): TVec3;

function Mat4Identity: TMat4;
function Mat4Multiply(const a, b: TMat4): TMat4;
function Mat4Translate(x, y, z: single): TMat4;
function Mat4Scale(s: single): TMat4;
function Mat4RotateX(radians: single): TMat4;
function Mat4RotateY(radians: single): TMat4;
function Mat4Perspective(fovYRadians, aspect, znear, zfar: single): TMat4;
function Mat4LookAt(const eye, center, up: TVec3): TMat4;

implementation

uses
  math;

function Vec3(x, y, z: single): TVec3;
begin
  Vec3.x := x; Vec3.y := y; Vec3.z := z;
end;

function Vec3Sub(const a, b: TVec3): TVec3;
begin
  Vec3Sub := Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
end;

function Vec3Cross(const a, b: TVec3): TVec3;
begin
  Vec3Cross := Vec3(a.y * b.z - a.z * b.y,
                    a.z * b.x - a.x * b.z,
                    a.x * b.y - a.y * b.x);
end;

function Vec3Normalize(const a: TVec3): TVec3;
var
  len: single;
begin
  len := sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
  if len < 1e-8 then
    Vec3Normalize := Vec3(0, 0, 0)
  else
    Vec3Normalize := Vec3(a.x / len, a.y / len, a.z / len);
end;

function Mat4Identity: TMat4;
var
  i: longint;
begin
  for i := 0 to 15 do
    Mat4Identity[i] := 0;
  Mat4Identity[0]  := 1;
  Mat4Identity[5]  := 1;
  Mat4Identity[10] := 1;
  Mat4Identity[15] := 1;
end;

function Mat4Multiply(const a, b: TMat4): TMat4;
{ Returns a*b. Each output column is a applied to the matching column of b. }
var
  c, r, k: longint;
  sum: single;
begin
  for c := 0 to 3 do
    for r := 0 to 3 do begin
      sum := 0;
      for k := 0 to 3 do
        sum := sum + a[k * 4 + r] * b[c * 4 + k];
      Mat4Multiply[c * 4 + r] := sum;
    end;
end;

function Mat4Translate(x, y, z: single): TMat4;
begin
  Mat4Translate := Mat4Identity;
  Mat4Translate[12] := x;
  Mat4Translate[13] := y;
  Mat4Translate[14] := z;
end;

function Mat4Scale(s: single): TMat4;
begin
  Mat4Scale := Mat4Identity;
  Mat4Scale[0]  := s;
  Mat4Scale[5]  := s;
  Mat4Scale[10] := s;
end;

function Mat4RotateX(radians: single): TMat4;
var
  c, s: single;
begin
  c := cos(radians); s := sin(radians);
  Mat4RotateX := Mat4Identity;
  Mat4RotateX[5]  := c;
  Mat4RotateX[6]  := s;
  Mat4RotateX[9]  := -s;
  Mat4RotateX[10] := c;
end;

function Mat4RotateY(radians: single): TMat4;
var
  c, s: single;
begin
  c := cos(radians); s := sin(radians);
  Mat4RotateY := Mat4Identity;
  Mat4RotateY[0]  := c;
  Mat4RotateY[2]  := -s;
  Mat4RotateY[8]  := s;
  Mat4RotateY[10] := c;
end;

function Mat4Perspective(fovYRadians, aspect, znear, zfar: single): TMat4;
var
  f: single;
  i: longint;
begin
  f := 1.0 / tan(fovYRadians / 2.0);
  for i := 0 to 15 do
    Mat4Perspective[i] := 0;
  Mat4Perspective[0]  := f / aspect;
  Mat4Perspective[5]  := f;
  Mat4Perspective[10] := (zfar + znear) / (znear - zfar);
  Mat4Perspective[11] := -1.0;
  Mat4Perspective[14] := (2.0 * zfar * znear) / (znear - zfar);
end;

function Mat4LookAt(const eye, center, up: TVec3): TMat4;
var
  f, s, u: TVec3;
begin
  f := Vec3Normalize(Vec3Sub(center, eye));
  s := Vec3Normalize(Vec3Cross(f, up));
  u := Vec3Cross(s, f);
  Mat4LookAt := Mat4Identity;
  Mat4LookAt[0]  := s.x;  Mat4LookAt[4]  := s.y;  Mat4LookAt[8]  := s.z;
  Mat4LookAt[1]  := u.x;  Mat4LookAt[5]  := u.y;  Mat4LookAt[9]  := u.z;
  Mat4LookAt[2]  := -f.x; Mat4LookAt[6]  := -f.y; Mat4LookAt[10] := -f.z;
  Mat4LookAt[12] := -(s.x * eye.x + s.y * eye.y + s.z * eye.z);
  Mat4LookAt[13] := -(u.x * eye.x + u.y * eye.y + u.z * eye.z);
  Mat4LookAt[14] :=  (f.x * eye.x + f.y * eye.y + f.z * eye.z);
end;

end.
