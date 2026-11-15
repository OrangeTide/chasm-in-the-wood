program voxelize;

{** Surface voxelizer: an OBJ mesh becomes a MagicaVoxel .vox.

  Reads an OBJ (and its referenced .mtl for per-material diffuse colour), fits the
  mesh into a voxel grid whose longest axis is the requested resolution, and marks
  every voxel a triangle passes through by point-sampling each triangle at roughly
  half-voxel spacing. OBJ is y-up and MagicaVoxel is z-up, so object y maps to
  voxel z; the runtime renderer undoes that to stand the model up.

  Usage: voxelize input.obj output.vox [resolution] }

{$mode objfpc}{$H+}

uses
  sysutils, classes, voxfile;

type
  TV3 = record x, y, z: single; end;

  TMaterial = record
    name: string;
    r, g, b: byte;
  end;

  TTri = record
    a, b, c: longint;      { indices into verts }
    colorIdx: byte;        { palette index 1..255 }
  end;

var
  verts: array of TV3;
  nverts: longint;
  tris: array of TTri;
  ntris: longint;
  mats: array of TMaterial;
  nmats: longint;
  palette: array[1..255] of TVoxRGBA;
  npal: longint;

{ ---- small helpers ---- }

procedure SplitTokens(const line: string; out toks: array of string; out n: longint);
var
  i, start, len: longint;
begin
  n := 0; i := 1; len := length(line);
  while i <= len do begin
    while (i <= len) and (line[i] <= ' ') do Inc(i);
    if i > len then break;
    start := i;
    while (i <= len) and (line[i] > ' ') do Inc(i);
    if n <= High(toks) then begin
      toks[n] := Copy(line, start, i - start);
      Inc(n);
    end;
  end;
end;

function FirstIndex(const tok: string): longint;
{ "12/3/4" or "12//4" or "12" -> 12, OBJ 1-based; negatives are relative. }
var
  s: string;
  p: longint;
begin
  p := Pos('/', tok);
  if p > 0 then s := Copy(tok, 1, p - 1) else s := tok;
  FirstIndex := StrToIntDef(s, 0);
end;

function PaletteIndex(r, g, b: byte): byte;
{ Find-or-add a colour; the voxel grid stores the returned index. }
var
  i: longint;
begin
  for i := 1 to npal do
    if (palette[i].r = r) and (palette[i].g = g) and (palette[i].b = b) then begin
      PaletteIndex := i; exit;
    end;
  if npal < 255 then begin
    Inc(npal);
    palette[npal].r := r; palette[npal].g := g;
    palette[npal].b := b; palette[npal].a := 255;
    PaletteIndex := npal;
  end else
    PaletteIndex := 1;   { palette full: fold onto the first colour }
end;

{ ---- MTL ---- }

procedure LoadMtl(const path: string);
var
  f: TextFile;
  line: string;
  toks: array[0..15] of string;
  n: longint;
begin
  if not FileExists(path) then exit;
  AssignFile(f, path);
  Reset(f);
  while not Eof(f) do begin
    ReadLn(f, line);
    SplitTokens(line, toks, n);
    if n = 0 then continue;
    if toks[0] = 'newmtl' then begin
      Inc(nmats);
      SetLength(mats, nmats);
      mats[nmats-1].name := toks[1];
      mats[nmats-1].r := 180; mats[nmats-1].g := 180; mats[nmats-1].b := 180;
    end
    else if (toks[0] = 'Kd') and (nmats > 0) and (n >= 4) then begin
      mats[nmats-1].r := Round(StrToFloatDef(toks[1], 0.7) * 255);
      mats[nmats-1].g := Round(StrToFloatDef(toks[2], 0.7) * 255);
      mats[nmats-1].b := Round(StrToFloatDef(toks[3], 0.7) * 255);
    end;
  end;
  CloseFile(f);
end;

function MaterialColor(const name: string): byte;
var
  i: longint;
begin
  for i := 0 to nmats - 1 do
    if mats[i].name = name then begin
      MaterialColor := PaletteIndex(mats[i].r, mats[i].g, mats[i].b);
      exit;
    end;
  MaterialColor := PaletteIndex(180, 180, 180);
end;

{ ---- OBJ ---- }

procedure LoadObj(const path: string);
var
  f: TextFile;
  line, curMtlName: string;
  toks: array[0..63] of string;
  n, i, ia, ib, ic: longint;
  curColor: byte;
  dir: string;

  function Resolve(idx: longint): longint;
  begin
    if idx > 0 then Resolve := idx - 1
    else if idx < 0 then Resolve := nverts + idx
    else Resolve := -1;
  end;

begin
  dir := ExtractFilePath(path);
  curMtlName := '';
  curColor := PaletteIndex(180, 180, 180);
  AssignFile(f, path);
  Reset(f);
  while not Eof(f) do begin
    ReadLn(f, line);
    SplitTokens(line, toks, n);
    if n = 0 then continue;
    if toks[0] = 'v' then begin
      Inc(nverts);
      if nverts > length(verts) then SetLength(verts, nverts * 2 + 64);
      verts[nverts-1].x := StrToFloatDef(toks[1], 0);
      verts[nverts-1].y := StrToFloatDef(toks[2], 0);
      verts[nverts-1].z := StrToFloatDef(toks[3], 0);
    end
    else if toks[0] = 'mtllib' then
      LoadMtl(dir + toks[1])
    else if toks[0] = 'usemtl' then begin
      curMtlName := toks[1];
      curColor := MaterialColor(curMtlName);
    end
    else if toks[0] = 'f' then begin
      { fan-triangulate the polygon }
      for i := 2 to n - 2 do begin
        ia := Resolve(FirstIndex(toks[1]));
        ib := Resolve(FirstIndex(toks[i]));
        ic := Resolve(FirstIndex(toks[i+1]));
        if (ia < 0) or (ib < 0) or (ic < 0) then continue;
        Inc(ntris);
        if ntris > length(tris) then SetLength(tris, ntris * 2 + 64);
        tris[ntris-1].a := ia; tris[ntris-1].b := ib; tris[ntris-1].c := ic;
        tris[ntris-1].colorIdx := curColor;
      end;
    end;
  end;
  CloseFile(f);
  SetLength(verts, nverts);
  SetLength(tris, ntris);
end;

{ ---- Voxelization ---- }

var
  m: TVoxModel;
  bbMin, bbMax: TV3;
  voxSize: single;

procedure ComputeBounds;
var
  i: longint;
begin
  bbMin := verts[0]; bbMax := verts[0];
  for i := 1 to nverts - 1 do begin
    if verts[i].x < bbMin.x then bbMin.x := verts[i].x;
    if verts[i].y < bbMin.y then bbMin.y := verts[i].y;
    if verts[i].z < bbMin.z then bbMin.z := verts[i].z;
    if verts[i].x > bbMax.x then bbMax.x := verts[i].x;
    if verts[i].y > bbMax.y then bbMax.y := verts[i].y;
    if verts[i].z > bbMax.z then bbMax.z := verts[i].z;
  end;
end;

procedure MarkPoint(px, py, pz: single; color: byte);
{ OBJ y-up -> voxel z-up: voxel (x, z, y) = obj (x, z, y)->(vx=x, vy=objZ, vz=objY) }
var
  vx, vy, vz: longint;
begin
  vx := Trunc((px - bbMin.x) / voxSize);
  vy := Trunc((pz - bbMin.z) / voxSize);
  vz := Trunc((py - bbMin.y) / voxSize);
  if vx >= m.sx then vx := m.sx - 1;
  if vy >= m.sy then vy := m.sy - 1;
  if vz >= m.sz then vz := m.sz - 1;
  if (vx >= 0) and (vy >= 0) and (vz >= 0) then
    VoxSetCell(m, vx, vy, vz, color);
end;

function Dist(const a, b: TV3): single;
begin
  Dist := sqrt(sqr(a.x-b.x) + sqr(a.y-b.y) + sqr(a.z-b.z));
end;

procedure VoxelizeTri(const t: TTri);
var
  v0, v1, v2: TV3;
  e1len, e2len: single;
  steps, i, j: longint;
  u, w: single;
  px, py, pz: single;
begin
  v0 := verts[t.a]; v1 := verts[t.b]; v2 := verts[t.c];
  e1len := Dist(v1, v0); e2len := Dist(v2, v0);
  steps := Trunc(2.0 * (e1len + e2len) / voxSize) + 2;
  for i := 0 to steps do
    for j := 0 to steps - i do begin
      u := i / steps;
      w := j / steps;
      px := v0.x + (v1.x - v0.x) * u + (v2.x - v0.x) * w;
      py := v0.y + (v1.y - v0.y) * u + (v2.y - v0.y) * w;
      pz := v0.z + (v1.z - v0.z) * u + (v2.z - v0.z) * w;
      MarkPoint(px, py, pz, t.colorIdx);
    end;
end;

var
  res, i: longint;
  ex, ey, ez, maxExt: single;
  nx, ny, nz: longint;
begin
  if ParamCount < 2 then begin
    writeln(StdErr, 'usage: voxelize input.obj output.vox [resolution]');
    halt(2);
  end;
  res := 48;
  if ParamCount >= 3 then res := StrToIntDef(ParamStr(3), 48);
  if res < 1 then res := 1;
  if res > 255 then res := 255;

  nverts := 0; ntris := 0; nmats := 0; npal := 0;
  LoadObj(ParamStr(1));
  if nverts = 0 then begin
    writeln(StdErr, 'voxelize: no vertices in ', ParamStr(1));
    halt(1);
  end;

  ComputeBounds;
  ex := bbMax.x - bbMin.x;
  ey := bbMax.y - bbMin.y;
  ez := bbMax.z - bbMin.z;
  maxExt := ex;
  if ey > maxExt then maxExt := ey;
  if ez > maxExt then maxExt := ez;
  if maxExt <= 0 then maxExt := 1;
  voxSize := maxExt / res;

  { grid dims: obj x->sx, obj z->sy, obj y->sz }
  nx := Trunc(ex / voxSize) + 1;
  ny := Trunc(ez / voxSize) + 1;
  nz := Trunc(ey / voxSize) + 1;
  if nx > 255 then nx := 255;
  if ny > 255 then ny := 255;
  if nz > 255 then nz := 255;
  VoxAlloc(m, nx, ny, nz);

  for i := 0 to ntris - 1 do
    VoxelizeTri(tris[i]);

  for i := 1 to 255 do m.palette[i] := palette[i];

  if not VoxSave(ParamStr(2), m) then begin
    writeln(StdErr, 'voxelize: could not write ', ParamStr(2));
    halt(1);
  end;
  writeln('voxelize: ', ParamStr(1), ' -> ', ParamStr(2),
          ' (', nx, 'x', ny, 'x', nz, ', ', VoxSolidCount(m), ' voxels, ',
          npal, ' colours)');
end.
