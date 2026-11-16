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
    Cx, Cy, Cz: LongInt;        { chunk coordinates in the global grid }
    Vox: TVoxModel;             { CHUNK^3 dense grid, world palette }
    Gpu: TGpuMesh;
    HasMesh: Boolean;
    Dirty: Boolean;
    Empty: Boolean;             { no solid voxels: nothing to draw }
    Mn, Mx: TVec3;              { world-space AABB, set from the voxel scale }
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
  c.Cx := cx; c.Cy := cy; c.Cz := cz;
  VoxAlloc(c.Vox, CHUNK, CHUNK, CHUNK);
  for i := 1 to 255 do
    if i - 1 <= High(palette) then c.Vox.Palette[i] := palette[i - 1];
  c.Dirty := True;
  c.Empty := True;
end;

procedure ChunkSet(var c: TChunk; lx, ly, lz: LongInt; v: Byte);
begin
  if (lx < 0) or (ly < 0) or (lz < 0) or
     (lx >= CHUNK) or (ly >= CHUNK) or (lz >= CHUNK) then exit;
  VoxSetCell(c.Vox, lx, ly, lz, v);
  c.Dirty := True;
  if v <> 0 then c.Empty := False;
end;

procedure ChunkRemesh(var c: TChunk; voxScale: Single);
var
  mesh: TVoxMesh;
  base: Single;
begin
  if not c.Dirty then exit;

  c.Empty := VoxSolidCount(c.Vox) = 0;
  if c.HasMesh then MeshFree(c.Gpu);
  c.HasMesh := False;

  if not c.Empty then begin
    BuildMesh(c.Vox, mesh);
    MeshUpload(c.Gpu, mesh);
    c.HasMesh := True;
  end;

  base := CHUNK * voxScale;
  c.Mn := Vec3(c.Cx * base, c.Cy * base, c.Cz * base);
  c.Mx := Vec3(c.Mn.X + base, c.Mn.Y + base, c.Mn.Z + base);
  c.Dirty := False;
end;

procedure ChunkFree(var c: TChunk);
begin
  if c.HasMesh then MeshFree(c.Gpu);
  c.HasMesh := False;
end;

end.
