unit vecmath;

{** Small 3D vector and 4x4 matrix helpers for the renderer.

  Matrices are column-major, the layout OpenGL expects, so a TMat4 can be handed
  straight to glUniformMatrix4fv with transpose = GL_FALSE. Element m[c*4 + r] is
  row r, column c. Angles are radians. }

{$mode objfpc}{$H+}

interface

type
  TVec3 = record
    X, Y, Z: Single;
  end;

  { Column-major 4x4. Index as m[col*4 + row]. }
  TMat4 = array[0..15] of Single;

function Vec3(x, y, z: Single): TVec3;
function Vec3Sub(const a, b: TVec3): TVec3;
function Vec3Cross(const a, b: TVec3): TVec3;
function Vec3Normalize(const a: TVec3): TVec3;

function Mat4Identity: TMat4;
function Mat4Multiply(const a, b: TMat4): TMat4;
function Mat4Translate(x, y, z: Single): TMat4;
function Mat4Scale(s: Single): TMat4;
function Mat4RotateX(radians: Single): TMat4;
function Mat4RotateY(radians: Single): TMat4;
function Mat4Perspective(fovYRadians, aspect, znear, zfar: Single): TMat4;
function Mat4LookAt(const eye, center, up: TVec3): TMat4;

implementation

uses
  math;

function Vec3(x, y, z: Single): TVec3;
begin
  Vec3.X := x; Vec3.Y := y; Vec3.Z := z;
end;

function Vec3Sub(const a, b: TVec3): TVec3;
begin
  Vec3Sub := Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
end;

function Vec3Cross(const a, b: TVec3): TVec3;
begin
  Vec3Cross := Vec3(a.Y * b.Z - a.Z * b.Y,
                    a.Z * b.X - a.X * b.Z,
                    a.X * b.Y - a.Y * b.X);
end;

function Vec3Normalize(const a: TVec3): TVec3;
var
  len: Single;
begin
  len := sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z);
  if len < 1e-8 then
    Vec3Normalize := Vec3(0, 0, 0)
  else
    Vec3Normalize := Vec3(a.X / len, a.Y / len, a.Z / len);
end;

function Mat4Identity: TMat4;
var
  i: LongInt;
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
  c, r, k: LongInt;
  sum: Single;
begin
  for c := 0 to 3 do
    for r := 0 to 3 do begin
      sum := 0;
      for k := 0 to 3 do
        sum := sum + a[k * 4 + r] * b[c * 4 + k];
      Mat4Multiply[c * 4 + r] := sum;
    end;
end;

function Mat4Translate(x, y, z: Single): TMat4;
begin
  Mat4Translate := Mat4Identity;
  Mat4Translate[12] := x;
  Mat4Translate[13] := y;
  Mat4Translate[14] := z;
end;

function Mat4Scale(s: Single): TMat4;
begin
  Mat4Scale := Mat4Identity;
  Mat4Scale[0]  := s;
  Mat4Scale[5]  := s;
  Mat4Scale[10] := s;
end;

function Mat4RotateX(radians: Single): TMat4;
var
  c, s: Single;
begin
  c := cos(radians); s := sin(radians);
  Mat4RotateX := Mat4Identity;
  Mat4RotateX[5]  := c;
  Mat4RotateX[6]  := s;
  Mat4RotateX[9]  := -s;
  Mat4RotateX[10] := c;
end;

function Mat4RotateY(radians: Single): TMat4;
var
  c, s: Single;
begin
  c := cos(radians); s := sin(radians);
  Mat4RotateY := Mat4Identity;
  Mat4RotateY[0]  := c;
  Mat4RotateY[2]  := -s;
  Mat4RotateY[8]  := s;
  Mat4RotateY[10] := c;
end;

function Mat4Perspective(fovYRadians, aspect, znear, zfar: Single): TMat4;
var
  f: Single;
  i: LongInt;
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
  Mat4LookAt[0]  := s.X;  Mat4LookAt[4]  := s.Y;  Mat4LookAt[8]  := s.Z;
  Mat4LookAt[1]  := u.X;  Mat4LookAt[5]  := u.Y;  Mat4LookAt[9]  := u.Z;
  Mat4LookAt[2]  := -f.X; Mat4LookAt[6]  := -f.Y; Mat4LookAt[10] := -f.Z;
  Mat4LookAt[12] := -(s.X * eye.X + s.Y * eye.Y + s.Z * eye.Z);
  Mat4LookAt[13] := -(u.X * eye.X + u.Y * eye.Y + u.Z * eye.Z);
  Mat4LookAt[14] :=  (f.X * eye.X + f.Y * eye.Y + f.Z * eye.Z);
end;

end.
