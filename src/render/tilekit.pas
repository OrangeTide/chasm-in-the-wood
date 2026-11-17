unit tilekit;

{** Baked meshes for the tiles, grouped by environment.

  The authored tiles are being replaced, so the kit now generates placeholder tiles by
  formula (see prims): a floor plate, a wall plate, a door arch, and a flight of steps
  for stairs. Each is built once in the file's z-up, rotated into the engine's y-up, and
  meshed to a single GPU mesh; every environment shares the same set for now. The world
  draws a cell by drawing its environment-and-kind mesh at the cell origin.

  Each mesh records its footprint and the caller scales it to fill one world cell. The
  generated footprint is TILE_FOOT voxels, so that scale equals the object voxel-unit and
  tiles sit on the same scale as the free-standing models. }

{$mode objfpc}{$H+}

interface

uses
  voxfile, voxmesh, gpumesh, prims;

type
  TTileEnv  = (teDungeon, teForest, teTown);
  TTileKind = (tkFloor, tkWall, tkDoor, tkStairUp, tkStairDn);

  TTileMesh = record
    Gpu:    TGpuMesh;
    Loaded: Boolean;
    Sx, Sy, Sz: LongInt;    { baked voxel dimensions, y up }
  end;

const
  TILE_GRID = 50;   { footprint clamp: the widest authored tile }
  TILE_MAXH = 64;   { height clamp }
  TILE_FOOT = 16;   { generated tile footprint: a cell is TILE_FOOT object voxels }
  TILE_WALLH = 40;  { generated wall and door height: well above the one-tile floor }
  TILE_STEPH = 30;  { generated stair height, so the steps climb clear of the floor }

{ Load and mesh every environment's tiles under baseDir (e.g. 'content/tiles'), from
  baseDir/<env>/<kind>.vox. Needs a live GL context. Returns False if a required tile
  (any floor or wall) is missing. }
function TileKitLoad(const baseDir: String): Boolean;

{ The baked mesh for an environment and kind. Doors and missing stairs fall back to
  the floor, so a caller can always draw something. }
function TileKitMesh(env: TTileEnv; kind: TTileKind): TTileMesh;

procedure TileKitFree;

implementation

var
  gKits: array[TTileEnv, TTileKind] of TTileMesh;

procedure BakeYUp(const src: TVoxModel; out dst: TVoxModel);
{ Rotate a z-up model into y-up (height along y), clamped to the grid. The source voxel
  (x, depth, height) becomes the baked voxel (x, height, depth). }
var
  nx, ny, nz, x, y, z: LongInt;
  v: Byte;
begin
  nx := src.Sx; if nx > TILE_GRID then nx := TILE_GRID;
  nz := src.Sy; if nz > TILE_GRID then nz := TILE_GRID;
  ny := src.Sz; if ny > TILE_MAXH then ny := TILE_MAXH;
  VoxAlloc(dst, nx, ny, nz);
  for z := 0 to nz - 1 do
    for y := 0 to ny - 1 do
      for x := 0 to nx - 1 do begin
        v := VoxCell(src, x, z, y);
        if v <> 0 then VoxSetCell(dst, x, y, z, v);
      end;
  dst.Palette := src.Palette;
end;

procedure MeshFrom(const src: TVoxModel; env: TTileEnv; kind: TTileKind);
{ Bake a z-up prim into y-up, mesh it, and store it as this env and kind's tile. }
var
  baked: TVoxModel;
  mesh: TVoxMesh;
begin
  BakeYUp(src, baked);
  BuildMesh(baked, mesh);
  GpuMeshUpload(gKits[env, kind].Gpu, mesh);
  gKits[env, kind].Sx := baked.Sx;
  gKits[env, kind].Sy := baked.Sy;
  gKits[env, kind].Sz := baked.Sz;
  gKits[env, kind].Loaded := True;
end;

function TileKitLoad(const baseDir: String): Boolean;
{ baseDir is ignored: the tiles are generated, not loaded. A floor is a plate one tile
  tall (so its top sits at the world floor height), a wall a taller plate, a door an
  arch, and the stairs a short flight of steps. Every environment uses the same set
  until authored tiles return. A footprint of TILE_FOOT voxels means a tile scales to
  the world cell by the object voxel-unit, so tiles and free-standing models share it. }
var
  env: TTileEnv;
  kind: TTileKind;
  floorP, wallP, doorP, stepP: TVoxModel;
begin
  for env := Low(TTileEnv) to High(TTileEnv) do
    for kind := Low(TTileKind) to High(TTileKind) do
      gKits[env, kind].Loaded := False;

  PrimPlate(floorP, TILE_FOOT, TILE_FOOT, TILE_FOOT);
  PrimPlate(wallP,  TILE_FOOT, TILE_FOOT, TILE_WALLH);
  PrimArch(doorP,   TILE_FOOT, TILE_FOOT, TILE_WALLH);
  PrimSteps(stepP,  TILE_FOOT, TILE_FOOT, TILE_STEPH, 5);

  for env := Low(TTileEnv) to High(TTileEnv) do begin
    MeshFrom(floorP, env, tkFloor);
    MeshFrom(wallP,  env, tkWall);
    MeshFrom(doorP,  env, tkDoor);
    MeshFrom(stepP,  env, tkStairDn);
    MeshFrom(stepP,  env, tkStairUp);
  end;
  TileKitLoad := True;
end;

function TileKitMesh(env: TTileEnv; kind: TTileKind): TTileMesh;
begin
  if gKits[env, kind].Loaded then
    TileKitMesh := gKits[env, kind]
  else
    TileKitMesh := gKits[env, tkFloor];   { doors and absent stairs show the floor }
end;

procedure TileKitFree;
var
  env: TTileEnv;
  kind: TTileKind;
begin
  for env := Low(TTileEnv) to High(TTileEnv) do
    for kind := Low(TTileKind) to High(TTileKind) do
      if gKits[env, kind].Loaded then begin
        GpuMeshFree(gKits[env, kind].Gpu);
        gKits[env, kind].Loaded := False;
      end;
end;

end.
