unit camera;

{** Diorama camera.

  The demo uses a fixed three-quarter view, but the camera is written as an orbit
  rig around a target point: yaw, pitch, and distance place the eye, and the eye
  always looks at the target. A follow camera later only has to move the target
  each frame; the framing math here does not change. }

{$mode objfpc}{$H+}

interface

uses
  vecmath;

type
  TCamera = record
    Target:   TVec3;    { point the eye looks at }
    Yaw:      Single;   { radians, orbit around world up }
    Pitch:    Single;   { radians, elevation above the target }
    Distance: Single;   { eye distance from the target }
    FovY:     Single;   { vertical field of view, radians }
    Aspect:   Single;   { viewport width / height }
    Znear:    Single;
    Zfar:     Single;
  end;

procedure CameraInitDiorama(out c: TCamera; aspect: Single);
function CameraEye(const c: TCamera): TVec3;
function CameraView(const c: TCamera): TMat4;
function CameraProj(const c: TCamera): TMat4;

implementation

uses
  math;

const
  DEG = pi / 180.0;

procedure CameraInitDiorama(out c: TCamera; aspect: Single);
begin
  c.Target   := Vec3(0, 0, 0);
  c.Yaw      := 45 * DEG;
  c.Pitch    := 30 * DEG;
  c.Distance := 4.0;
  c.FovY     := 45 * DEG;
  c.Aspect   := aspect;
  c.Znear    := 0.1;
  c.Zfar     := 100.0;
end;

function CameraEye(const c: TCamera): TVec3;
var
  dir: TVec3;
begin
  dir.X := cos(c.Pitch) * sin(c.Yaw);
  dir.Y := sin(c.Pitch);
  dir.Z := cos(c.Pitch) * cos(c.Yaw);
  CameraEye := Vec3(c.Target.X + dir.X * c.Distance,
                    c.Target.Y + dir.Y * c.Distance,
                    c.Target.Z + dir.Z * c.Distance);
end;

function CameraView(const c: TCamera): TMat4;
begin
  CameraView := Mat4LookAt(CameraEye(c), c.Target, Vec3(0, 1, 0));
end;

function CameraProj(const c: TCamera): TMat4;
begin
  CameraProj := Mat4Perspective(c.FovY, c.Aspect, c.Znear, c.Zfar);
end;

end.
