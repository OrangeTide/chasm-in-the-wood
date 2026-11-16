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
    target:   TVec3;    { point the eye looks at }
    yaw:      Single;   { radians, orbit around world up }
    pitch:    Single;   { radians, elevation above the target }
    distance: Single;   { eye distance from the target }
    fovY:     Single;   { vertical field of view, radians }
    aspect:   Single;   { viewport width / height }
    znear:    Single;
    zfar:     Single;
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
  c.target   := Vec3(0, 0, 0);
  c.yaw      := 45 * DEG;
  c.pitch    := 30 * DEG;
  c.distance := 4.0;
  c.fovY     := 45 * DEG;
  c.aspect   := aspect;
  c.znear    := 0.1;
  c.zfar     := 100.0;
end;

function CameraEye(const c: TCamera): TVec3;
var
  dir: TVec3;
begin
  dir.x := cos(c.pitch) * sin(c.yaw);
  dir.y := sin(c.pitch);
  dir.z := cos(c.pitch) * cos(c.yaw);
  CameraEye := Vec3(c.target.x + dir.x * c.distance,
                    c.target.y + dir.y * c.distance,
                    c.target.z + dir.z * c.distance);
end;

function CameraView(const c: TCamera): TMat4;
begin
  CameraView := Mat4LookAt(CameraEye(c), c.target, Vec3(0, 1, 0));
end;

function CameraProj(const c: TCamera): TMat4;
begin
  CameraProj := Mat4Perspective(c.fovY, c.aspect, c.znear, c.zfar);
end;

end.
