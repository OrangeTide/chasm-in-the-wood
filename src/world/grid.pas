unit grid;

{** The dungeon floor grid.

  A flat field of square cells the player and, later, monsters stand on. The grid
  is centred on the world origin so the scene sits around (0,0). This unit knows
  the cell-to-world mapping and builds a floor mesh; it does not know about the
  renderer beyond producing a TVoxMesh to upload. }

{$mode objfpc}{$H+}

interface

uses
  vecmath, voxmesh;

const
  CELL = 1.0;   { world units per cell edge }

type
  TGrid = record
    w, h: longint;   { cells along x and z }
  end;

procedure GridInit(out g: TGrid; w, h: longint);
function GridInBounds(const g: TGrid; cx, cy: longint): boolean;
function GridCellCenter(const g: TGrid; cx, cy: longint): TVec3;
procedure GridBuildFloor(const g: TGrid; out mesh: TVoxMesh);

implementation

procedure GridInit(out g: TGrid; w, h: longint);
begin
  g.w := w; g.h := h;
end;

function GridInBounds(const g: TGrid; cx, cy: longint): boolean;
begin
  GridInBounds := (cx >= 0) and (cy >= 0) and (cx < g.w) and (cy < g.h);
end;

function GridCellCenter(const g: TGrid; cx, cy: longint): TVec3;
{ Cell (cx,cy) maps to the x/z plane at y=0, centred on the origin. }
begin
  GridCellCenter := Vec3((cx - g.w / 2.0 + 0.5) * CELL, 0,
                         (cy - g.h / 2.0 + 0.5) * CELL);
end;

procedure PutVert(var mesh: TVoxMesh; i: longint; x, z, r, gr, b: single);
begin
  mesh.verts[i].px := x;  mesh.verts[i].py := 0;  mesh.verts[i].pz := z;
  mesh.verts[i].nx := 0;  mesh.verts[i].ny := 1;  mesh.verts[i].nz := 0;
  mesh.verts[i].r := r;   mesh.verts[i].g := gr;  mesh.verts[i].b := b;
end;

procedure GridBuildFloor(const g: TGrid; out mesh: TVoxMesh);
{ One upward-facing quad per cell, two-tone by checker parity so motion reads. }
var
  cx, cy, vi, ii, base: longint;
  x0, z0, x1, z1: single;
  r, gr, b: single;
begin
  mesh.nverts := g.w * g.h * 4;
  mesh.nindices := g.w * g.h * 6;
  SetLength(mesh.verts, mesh.nverts);
  SetLength(mesh.indices, mesh.nindices);

  vi := 0; ii := 0;
  for cy := 0 to g.h - 1 do
    for cx := 0 to g.w - 1 do begin
      x0 := (cx - g.w / 2.0) * CELL;  x1 := x0 + CELL;
      z0 := (cy - g.h / 2.0) * CELL;  z1 := z0 + CELL;
      if ((cx + cy) and 1) = 0 then begin
        r := 0.26; gr := 0.28; b := 0.32;
      end else begin
        r := 0.20; gr := 0.22; b := 0.26;
      end;

      base := vi;
      PutVert(mesh, vi,   x0, z0, r, gr, b); Inc(vi);
      PutVert(mesh, vi,   x0, z1, r, gr, b); Inc(vi);
      PutVert(mesh, vi,   x1, z1, r, gr, b); Inc(vi);
      PutVert(mesh, vi,   x1, z0, r, gr, b); Inc(vi);

      { +y normal, CCW seen from above }
      mesh.indices[ii] := base + 0; mesh.indices[ii+1] := base + 1;
      mesh.indices[ii+2] := base + 2; Inc(ii, 3);
      mesh.indices[ii] := base + 0; mesh.indices[ii+1] := base + 2;
      mesh.indices[ii+2] := base + 3; Inc(ii, 3);
    end;
end;

end.
