unit voxchunk;

{** A cubic block of world voxels with a cached mesh.

  The chunk is the unit of meshing, GPU upload, and (later) streaming and culling.
  Voxels are stored densely in a CHUNK^3 grid sharing the world palette. When a
  chunk is dirty it is greedy-meshed and re-uploaded. Faces at the chunk border
  are meshed as if the outside were empty; neighbour-aware meshing to drop those
  hidden seam faces is a later optimisation. }

{$mode objfpc}{$H+}

interface

uses
  vecmath, voxfile, voxmesh, gpumesh, meshbackend;

const
  CHUNK = 16;   { voxels per edge }

type
  TChunk = record
    cx, cy, cz: LongInt;        { chunk coordinates in the global grid }
    vox: TVoxModel;             { CHUNK^3 dense grid, world palette }
    gpu: TGpuMesh;
    hasMesh: Boolean;
    dirty: Boolean;
    empty: Boolean;             { no solid voxels: nothing to draw }
    mn, mx: TVec3;              { world-space AABB, set from the voxel scale }
  end;

procedure ChunkInit(out c: TChunk; cx, cy, cz: LongInt;
  const palette: array of TVoxRGBA);
procedure ChunkSet(var c: TChunk; lx, ly, lz: LongInt; v: Byte);
procedure ChunkRemesh(var c: TChunk; voxScale: Single);
procedure ChunkFree(var c: TChunk);

implementation

procedure ChunkInit(out c: TChunk; cx, cy, cz: LongInt;
  const palette: array of TVoxRGBA);
var
  i: LongInt;
begin
  FillChar(c, SizeOf(c), 0);
  c.cx := cx; c.cy := cy; c.cz := cz;
  VoxAlloc(c.vox, CHUNK, CHUNK, CHUNK);
  for i := 1 to 255 do
    if i - 1 <= High(palette) then c.vox.palette[i] := palette[i - 1];
  c.dirty := True;
  c.empty := True;
end;

procedure ChunkSet(var c: TChunk; lx, ly, lz: LongInt; v: Byte);
begin
  if (lx < 0) or (ly < 0) or (lz < 0) or
     (lx >= CHUNK) or (ly >= CHUNK) or (lz >= CHUNK) then exit;
  VoxSetCell(c.vox, lx, ly, lz, v);
  c.dirty := True;
  if v <> 0 then c.empty := False;
end;

procedure ChunkRemesh(var c: TChunk; voxScale: Single);
var
  mesh: TVoxMesh;
  base: Single;
begin
  if not c.dirty then exit;

  c.empty := VoxSolidCount(c.vox) = 0;
  if c.hasMesh then MeshFree(c.gpu);
  c.hasMesh := False;

  if not c.empty then begin
    BuildMesh(c.vox, mesh);
    MeshUpload(c.gpu, mesh);
    c.hasMesh := True;
  end;

  base := CHUNK * voxScale;
  c.mn := Vec3(c.cx * base, c.cy * base, c.cz * base);
  c.mx := Vec3(c.mn.x + base, c.mn.y + base, c.mn.z + base);
  c.dirty := False;
end;

procedure ChunkFree(var c: TChunk);
begin
  if c.hasMesh then MeshFree(c.gpu);
  c.hasMesh := False;
end;

end.
