unit meshbackend;

{** Swappable mesh residency backend.

  Chunk meshing is CPU work, but uploading a mesh to the GPU, freeing it, and
  drawing it need a live OpenGL context. Routing those three operations through
  procedure hooks lets the world's streaming logic run without GL: a test wires a
  null backend and drives load and evict with no context, while the game wires the
  real GL backend. The default is GL, so the game needs no setup. }

{$mode objfpc}{$H+}

interface

uses
  voxmesh, gpumesh;

type
  TMeshUpload = procedure(out g: TGpuMesh; const mesh: TVoxMesh);
  TMeshFree   = procedure(var g: TGpuMesh);
  TMeshDraw   = procedure(const g: TGpuMesh);

var
  MeshUpload: TMeshUpload;
  MeshFree:   TMeshFree;
  MeshDraw:   TMeshDraw;

procedure MeshBackendUseGL;
procedure MeshBackendUseNull;

implementation

procedure NullUpload(out g: TGpuMesh; const mesh: TVoxMesh);
begin
  FillChar(g, SizeOf(g), 0);
end;

procedure NullFree(var g: TGpuMesh);
begin
end;

procedure NullDraw(const g: TGpuMesh);
begin
end;

procedure MeshBackendUseGL;
begin
  MeshUpload := @GpuMeshUpload;
  MeshFree   := @GpuMeshFree;
  MeshDraw   := @GpuMeshDraw;
end;

procedure MeshBackendUseNull;
begin
  MeshUpload := @NullUpload;
  MeshFree   := @NullFree;
  MeshDraw   := @NullDraw;
end;

initialization
  MeshBackendUseGL;
end.
