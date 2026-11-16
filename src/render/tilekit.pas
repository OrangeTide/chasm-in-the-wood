unit tilekit;

{** Baked meshes for the authored tiles, grouped by environment.

  The world has three looks, each with its own authored tile set: the dungeon (brick),
  the forest (grass and trees), and the town (packed earth and stone cottages). Each
  tile kind in each environment is one authored MagicaVoxel model, the same in every
  cell of that kind, so the kit loads it once, rotates it from the file's z-up into the
  engine's y-up, and meshes it to a single GPU mesh. The world draws a cell by drawing
  its environment-and-kind mesh at the cell origin.

  The sets come from different packs at different native resolutions (the dungeon brick
  is 50 voxels across, the forest grass 16), so each mesh records its footprint and the
  caller scales it to fill one world cell. That lets the detailed dungeon and the chunky
  forest share one grid. }

{$mode objfpc}{$H+}

interface

uses
  sysutils, voxfile, voxmesh, gpumesh;

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

function LoadOne(const path: String; env: TTileEnv; kind: TTileKind): Boolean;
var
  src, baked: TVoxModel;
  mesh: TVoxMesh;
begin
  LoadOne := False;
  if not VoxLoad(path, src) then exit;
  BakeYUp(src, baked);
  BuildMesh(baked, mesh);
  GpuMeshUpload(gKits[env, kind].Gpu, mesh);
  gKits[env, kind].Sx := baked.Sx;
  gKits[env, kind].Sy := baked.Sy;
  gKits[env, kind].Sz := baked.Sz;
  gKits[env, kind].Loaded := True;
  LoadOne := True;
end;

function LoadEnv(const dir: String; env: TTileEnv): Boolean;
begin
  { Floor and wall are required; stairs are optional (the forest has none). }
  LoadEnv := LoadOne(dir + '/floor.vox', env, tkFloor) and
             LoadOne(dir + '/wall.vox',  env, tkWall);
  if FileExists(dir + '/stairs.vox') then begin
    LoadOne(dir + '/stairs.vox', env, tkStairDn);
    LoadOne(dir + '/stairs.vox', env, tkStairUp);
  end;
end;

function TileKitLoad(const baseDir: String): Boolean;
var
  env: TTileEnv;
  kind: TTileKind;
begin
  for env := Low(TTileEnv) to High(TTileEnv) do
    for kind := Low(TTileKind) to High(TTileKind) do
      gKits[env, kind].Loaded := False;
  TileKitLoad := LoadEnv(baseDir + '/dungeon', teDungeon) and
                 LoadEnv(baseDir + '/forest',  teForest) and
                 LoadEnv(baseDir + '/town',    teTown);
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
