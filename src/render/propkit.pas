unit propkit;

{** Baked meshes for the authored loot props.

  A prop dropped in the dungeon (treasure, a potion, a light, or sundry) is drawn as a
  small authored object standing on its tile, instead of the old coloured cube. Like the
  creatures, each prop is one authored MagicaVoxel model kept in its file's z-up
  orientation; the caller stands it upright with the same base transform the player and
  monsters use. The kit loads and meshes each kind once and hands back the mesh and its
  voxel dimensions. }

{$mode objfpc}{$H+}

interface

uses
  sysutils, voxfile, voxmesh, gpumesh;

type
  TPropKind = (pkTreasure, pkPotion, pkLight, pkMisc);

  TPropMesh = record
    Gpu:    TGpuMesh;
    Loaded: Boolean;
    Sx, Sy, Sz: LongInt;   { native voxel dimensions, z up }
  end;

{ Load and mesh the prop models under dir, from dir/<kind>.vox. Needs a live GL context.
  A missing kind is left unloaded and simply not drawn. Returns False only if none
  loaded. }
function PropKitLoad(const dir: String): Boolean;

function PropKitMesh(kind: TPropKind): TPropMesh;

procedure PropKitFree;

implementation

var
  gProps: array[TPropKind] of TPropMesh;

function LoadOne(const path: String; kind: TPropKind): Boolean;
var
  m: TVoxModel;
  mesh: TVoxMesh;
begin
  LoadOne := False;
  if not FileExists(path) then exit;
  if not VoxLoad(path, m) then exit;
  BuildMesh(m, mesh);
  GpuMeshUpload(gProps[kind].Gpu, mesh);
  gProps[kind].Sx := m.Sx;
  gProps[kind].Sy := m.Sy;
  gProps[kind].Sz := m.Sz;
  gProps[kind].Loaded := True;
  LoadOne := True;
end;

function PropKitLoad(const dir: String): Boolean;
var
  k: TPropKind;
  any: Boolean;
begin
  for k := Low(TPropKind) to High(TPropKind) do gProps[k].Loaded := False;
  any := False;
  any := LoadOne(dir + '/treasure.vox', pkTreasure) or any;
  any := LoadOne(dir + '/potion.vox',   pkPotion) or any;
  any := LoadOne(dir + '/light.vox',    pkLight) or any;
  any := LoadOne(dir + '/misc.vox',     pkMisc) or any;
  PropKitLoad := any;
end;

function PropKitMesh(kind: TPropKind): TPropMesh;
begin
  PropKitMesh := gProps[kind];
end;

procedure PropKitFree;
var
  k: TPropKind;
begin
  for k := Low(TPropKind) to High(TPropKind) do
    if gProps[k].Loaded then begin
      GpuMeshFree(gProps[k].Gpu);
      gProps[k].Loaded := False;
    end;
end;

end.
