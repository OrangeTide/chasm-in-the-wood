unit voxmesh;

{** Greedy mesher: a voxel grid becomes a compact triangle mesh.

  For each of the six face directions the mesher sweeps the grid in slices, marks
  the voxel faces that are exposed (solid voxel, empty neighbour), and merges runs
  of same-colour faces into the largest rectangles it can before emitting two
  triangles each. This collapses flat same-colour regions into a few large quads
  instead of one quad per voxel face.

  Geometry stays in voxel space (x,y,z with z up, as the file stores it). The
  renderer centres and rotates it to its y-up world, so nothing here needs to know
  about the camera. Each vertex carries position, face normal, and RGB colour. }

{$mode objfpc}{$H+}

interface

uses
  voxfile;

type
  TMeshVertex = packed record
    px, py, pz: Single;
    nx, ny, nz: Single;
    r, g, b:    Single;
  end;

  TVoxMesh = record
    verts:   array of TMeshVertex;
    indices: array of LongWord;
    nverts:  LongInt;
    nindices: LongInt;
  end;

procedure BuildMesh(const m: TVoxModel; out mesh: TVoxMesh);

implementation

var
  { Working mask for the current slice, reused across slices. }
  mask: array of LongInt;

procedure EnsureVertCap(var mesh: TVoxMesh; extra: LongInt);
begin
  if mesh.nverts + extra > length(mesh.verts) then
    SetLength(mesh.verts, (mesh.nverts + extra) * 2 + 64);
end;

procedure EnsureIndexCap(var mesh: TVoxMesh; extra: LongInt);
begin
  if mesh.nindices + extra > length(mesh.indices) then
    SetLength(mesh.indices, (mesh.nindices + extra) * 2 + 64);
end;

function AddVertex(var mesh: TVoxMesh; const p, n: array of Single;
  r, g, b: Single): LongWord;
begin
  EnsureVertCap(mesh, 1);
  mesh.verts[mesh.nverts].px := p[0];
  mesh.verts[mesh.nverts].py := p[1];
  mesh.verts[mesh.nverts].pz := p[2];
  mesh.verts[mesh.nverts].nx := n[0];
  mesh.verts[mesh.nverts].ny := n[1];
  mesh.verts[mesh.nverts].nz := n[2];
  mesh.verts[mesh.nverts].r := r;
  mesh.verts[mesh.nverts].g := g;
  mesh.verts[mesh.nverts].b := b;
  AddVertex := mesh.nverts;
  Inc(mesh.nverts);
end;

procedure AddTri(var mesh: TVoxMesh; a, b, c: LongWord);
begin
  EnsureIndexCap(mesh, 3);
  mesh.indices[mesh.nindices]   := a;
  mesh.indices[mesh.nindices+1] := b;
  mesh.indices[mesh.nindices+2] := c;
  Inc(mesh.nindices, 3);
end;

procedure BuildMesh(const m: TVoxModel; out mesh: TVoxMesh);
var
  dims: array[0..2] of LongInt;
  ax, u, v, sgn, dir: LongInt;
  a, iu, iv, w, rh, k, cidx, cu, cv: LongInt;
  du, dv, plane, nb: LongInt;
  cell, pos: array[0..2] of LongInt;
  n: array[0..2] of Single;
  c00, c10, c11, c01: LongWord;
  cr, cg, cb: Single;
  done: Boolean;

  function Corner(aC, uC, vC: LongInt): LongWord;
  var
    p: array[0..2] of Single;
  begin
    p[ax] := aC; p[u] := uC; p[v] := vC;
    Corner := AddVertex(mesh, p, n, cr, cg, cb);
  end;

begin
  mesh.nverts := 0;
  mesh.nindices := 0;
  SetLength(mesh.verts, 0);
  SetLength(mesh.indices, 0);
  dims[0] := m.sx; dims[1] := m.sy; dims[2] := m.sz;

  for ax := 0 to 2 do begin
    u := (ax + 1) mod 3;
    v := (ax + 2) mod 3;
    du := dims[u];
    dv := dims[v];
    SetLength(mask, du * dv);

    for dir := 0 to 1 do begin
      if dir = 0 then sgn := 1 else sgn := -1;
      n[0] := 0; n[1] := 0; n[2] := 0;
      n[ax] := sgn;

      for a := 0 to dims[ax] - 1 do begin
        { Build the exposed-face mask for this slice. }
        for iv := 0 to dv - 1 do
          for iu := 0 to du - 1 do begin
            cell[ax] := a; cell[u] := iu; cell[v] := iv;
            cidx := VoxCell(m, cell[0], cell[1], cell[2]);
            if cidx = 0 then begin
              mask[iu + iv * du] := 0;
              continue;
            end;
            pos[ax] := a + sgn; pos[u] := iu; pos[v] := iv;
            nb := VoxCell(m, pos[0], pos[1], pos[2]);
            if nb <> 0 then mask[iu + iv * du] := 0   { face hidden }
            else mask[iu + iv * du] := cidx;
          end;

        { Greedily merge equal-colour rectangles out of the mask. }
        if sgn > 0 then plane := a + 1 else plane := a;
        for iv := 0 to dv - 1 do begin
          iu := 0;
          while iu < du do begin
            cidx := mask[iu + iv * du];
            if cidx = 0 then begin Inc(iu); continue; end;
            { widest run of this colour along u }
            w := 1;
            while (iu + w < du) and (mask[iu + w + iv * du] = cidx) do Inc(w);
            { tallest extent along v for which the whole width matches }
            rh := 1; done := False;
            while (iv + rh < dv) and not done do begin
              for k := 0 to w - 1 do
                if mask[iu + k + (iv + rh) * du] <> cidx then begin
                  done := True; break;
                end;
              if not done then Inc(rh);
            end;

            cr := m.palette[cidx].r / 255.0;
            cg := m.palette[cidx].g / 255.0;
            cb := m.palette[cidx].b / 255.0;
            c00 := Corner(plane, iu,     iv);
            c10 := Corner(plane, iu + w,  iv);
            c11 := Corner(plane, iu + w,  iv + rh);
            c01 := Corner(plane, iu,     iv + rh);
            { U x V points along +ax, so +sgn faces wind u-then-v; -sgn reverses. }
            if sgn > 0 then begin
              AddTri(mesh, c00, c10, c11);
              AddTri(mesh, c00, c11, c01);
            end else begin
              AddTri(mesh, c00, c11, c10);
              AddTri(mesh, c00, c01, c11);
            end;

            { consume the rectangle so it is not emitted again }
            for cv := iv to iv + rh - 1 do
              for cu := iu to iu + w - 1 do
                mask[cu + cv * du] := 0;
            Inc(iu, w);
          end;
        end;
      end;
    end;
  end;

  SetLength(mesh.verts, mesh.nverts);
  SetLength(mesh.indices, mesh.nindices);
end;

end.
