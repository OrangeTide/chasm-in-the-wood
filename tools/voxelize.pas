program voxelize;

{** Solid voxelizer: an OBJ mesh becomes a MagicaVoxel .vox.

  Reads an OBJ (and its referenced .mtl for per-material colour), fits the mesh into a
  voxel grid whose longest axis is the requested resolution, and marks every voxel a
  triangle passes through by point-sampling each triangle at roughly half-voxel spacing.
  OBJ is y-up and MagicaVoxel is z-up, so object y maps to voxel z; the runtime renderer
  undoes that to stand the model up.

  A material's colour is its diffuse `Kd` when the .mtl gives one. When the material is
  textured instead (a `map_Kd` image, as the texture-atlas kits use), the texture is read
  and each surface sample takes the texture's colour at its interpolated UV, so a brick or
  plaster face comes out with its real colours rather than one flat tone. The texture path
  in the .mtl is often an absolute authoring path, so only its file name is kept and the
  image is looked for beside the .mtl and in a Textures/ folder next to it.

  That surface pass alone leaves a closed mesh as a hollow shell, so by default a
  solid pass follows: flood the empty space inward from the grid boundary, then fill
  every empty voxel the flood never reached, which is the interior enclosed by the
  shell. A watertight wall or floor comes out solid; an open shape (a plane, a grate)
  has no enclosed interior and is left as its surface. Pass `surface` as the fourth
  argument to skip the solid pass and keep the bare shell.

  Usage: voxelize input.obj output.vox [resolution] [surface] }

{$mode objfpc}{$H+}

uses
  sysutils, classes, voxfile, FPImage, FPReadPNG;

type
  TV3 = record x, y, z: single; end;
  TUV = record u, v: single; end;

  TMaterial = record
    name: string;
    r, g, b: byte;
    hasTex: boolean;         { a map_Kd texture to sample instead of the flat colour }
    tex: TFPMemoryImage;
    texW, texH: longint;
  end;

  TTri = record
    a, b, c: longint;        { indices into verts }
    ua, ub, uc: longint;     { indices into uvs, -1 when the face has no texture coords }
    mat: longint;            { index into mats, -1 when none is bound }
    colorIdx: byte;          { flat palette index, used when the material is untextured }
  end;

var
  verts: array of TV3;
  nverts: longint;
  uvs: array of TUV;
  nuvs: longint;
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

function SecondIndex(const tok: string): longint;
{ The texture-coord index of "v/vt/vn", "v/vt" -> vt (OBJ 1-based); 0 when absent, as in
  "12" or "12//4". Negatives are relative. }
var
  p, q: longint;
  s: string;
begin
  p := Pos('/', tok);
  if p = 0 then exit(0);
  s := Copy(tok, p + 1, Length(tok));
  q := Pos('/', s);
  if q > 0 then s := Copy(s, 1, q - 1);
  SecondIndex := StrToIntDef(s, 0);
end;

function PaletteIndex(r, g, b: byte): byte;
{ Find-or-add a colour; the voxel grid stores the returned index. }
var
  i, best, bd, d, dr, dg, db: longint;
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
    exit;
  end;
  { Palette full: fold onto the nearest existing colour, so a texture with many shades
    degrades to its closest palette entries rather than collapsing to one. }
  best := 1; bd := High(longint);
  for i := 1 to npal do begin
    dr := longint(palette[i].r) - r;
    dg := longint(palette[i].g) - g;
    db := longint(palette[i].b) - b;
    d := dr * dr + dg * dg + db * db;
    if d < bd then begin bd := d; best := i; end;
  end;
  PaletteIndex := best;
end;

{ ---- MTL ---- }

function ValueAfter(const line, key: string): string;
{ The remainder of a line after the keyword, trimmed. Keeps spaces, so a texture path with
  spaces survives (SplitTokens would cut it at the first space). }
var
  p: longint;
begin
  p := Pos(key, line);
  if p = 0 then exit('');
  ValueAfter := Trim(Copy(line, p + Length(key), Length(line)));
end;

function LoadTexture(const mtlDir, raw: string; out img: TFPMemoryImage;
  out w, h: longint): boolean;
{ Load the map_Kd image. The path in the .mtl is often an absolute authoring path, so only
  its file name is used, looked for beside the .mtl and in a sibling Textures/ folder. }
var
  base, cand: string;
  tried: array[0..3] of string;
  i: longint;
begin
  LoadTexture := False;
  base := StringReplace(raw, '\', '/', [rfReplaceAll]);
  base := ExtractFileName(base);
  if base = '' then exit;
  tried[0] := mtlDir + base;
  tried[1] := mtlDir + 'Textures/' + base;
  tried[2] := mtlDir + 'textures/' + base;
  tried[3] := mtlDir + '../Textures/' + base;
  cand := '';
  for i := 0 to High(tried) do
    if FileExists(tried[i]) then begin cand := tried[i]; break; end;
  if cand = '' then exit;
  img := TFPMemoryImage.Create(0, 0);
  try
    img.LoadFromFile(cand);
    w := img.Width; h := img.Height;
    LoadTexture := (w > 0) and (h > 0);
  except
    FreeAndNil(img);
    LoadTexture := False;
  end;
end;

procedure LoadMtl(const path: string);
var
  f: TextFile;
  line, dir, raw: string;
  toks: array[0..15] of string;
  n: longint;
  img: TFPMemoryImage;
  tw, th: longint;
begin
  if not FileExists(path) then exit;
  dir := ExtractFilePath(path);
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
      mats[nmats-1].hasTex := False;
      mats[nmats-1].tex := nil;
    end
    else if (toks[0] = 'Kd') and (nmats > 0) and (n >= 4) then begin
      mats[nmats-1].r := Round(StrToFloatDef(toks[1], 0.7) * 255);
      mats[nmats-1].g := Round(StrToFloatDef(toks[2], 0.7) * 255);
      mats[nmats-1].b := Round(StrToFloatDef(toks[3], 0.7) * 255);
    end
    else if (toks[0] = 'map_Kd') and (nmats > 0) and (not mats[nmats-1].hasTex) then begin
      raw := ValueAfter(line, 'map_Kd');
      if LoadTexture(dir, raw, img, tw, th) then begin
        mats[nmats-1].hasTex := True;
        mats[nmats-1].tex := img;
        mats[nmats-1].texW := tw;
        mats[nmats-1].texH := th;
      end;
    end;
  end;
  CloseFile(f);
end;

function FindMat(const name: string): longint;
var
  i: longint;
begin
  for i := 0 to nmats - 1 do
    if mats[i].name = name then exit(i);
  FindMat := -1;
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
  n, i, ia, ib, ic, ja, jb, jc, curMat: longint;
  curColor: byte;
  dir: string;

  function Resolve(idx: longint): longint;
  begin
    if idx > 0 then Resolve := idx - 1
    else if idx < 0 then Resolve := nverts + idx
    else Resolve := -1;
  end;

  function ResolveUV(idx: longint): longint;
  begin
    if idx > 0 then ResolveUV := idx - 1
    else if idx < 0 then ResolveUV := nuvs + idx
    else ResolveUV := -1;
  end;

begin
  dir := ExtractFilePath(path);
  curMtlName := '';
  curColor := PaletteIndex(180, 180, 180);
  curMat := -1;
  AssignFile(f, path);
  Reset(f);
  while not Eof(f) do begin
    ReadLn(f, line);
    SplitTokens(line, toks, n);
    if n = 0 then continue;
    if (toks[0] = 'v') and (n >= 4) then begin
      Inc(nverts);
      if nverts > length(verts) then SetLength(verts, nverts * 2 + 64);
      verts[nverts-1].x := StrToFloatDef(toks[1], 0);
      verts[nverts-1].y := StrToFloatDef(toks[2], 0);
      verts[nverts-1].z := StrToFloatDef(toks[3], 0);
    end
    else if (toks[0] = 'vt') and (n >= 3) then begin
      Inc(nuvs);
      if nuvs > length(uvs) then SetLength(uvs, nuvs * 2 + 64);
      uvs[nuvs-1].u := StrToFloatDef(toks[1], 0);
      uvs[nuvs-1].v := StrToFloatDef(toks[2], 0);
    end
    else if toks[0] = 'mtllib' then
      LoadMtl(dir + toks[1])
    else if toks[0] = 'usemtl' then begin
      curMtlName := toks[1];
      curColor := MaterialColor(curMtlName);
      curMat := FindMat(curMtlName);
    end
    else if toks[0] = 'f' then begin
      { fan-triangulate the polygon }
      for i := 2 to n - 2 do begin
        ia := Resolve(FirstIndex(toks[1]));
        ib := Resolve(FirstIndex(toks[i]));
        ic := Resolve(FirstIndex(toks[i+1]));
        if (ia < 0) or (ib < 0) or (ic < 0) then continue;
        ja := ResolveUV(SecondIndex(toks[1]));
        jb := ResolveUV(SecondIndex(toks[i]));
        jc := ResolveUV(SecondIndex(toks[i+1]));
        Inc(ntris);
        if ntris > length(tris) then SetLength(tris, ntris * 2 + 64);
        tris[ntris-1].a := ia; tris[ntris-1].b := ib; tris[ntris-1].c := ic;
        tris[ntris-1].ua := ja; tris[ntris-1].ub := jb; tris[ntris-1].uc := jc;
        tris[ntris-1].mat := curMat;
        tris[ntris-1].colorIdx := curColor;
      end;
    end;
  end;
  CloseFile(f);
  SetLength(verts, nverts);
  SetLength(uvs, nuvs);
  SetLength(tris, ntris);
end;

{ ---- Voxelization ---- }

var
  m: TVoxModel;
  bbMin, bbMax: TV3;
  voxSize: single;
  { Sampling-grid phase offset, in voxel fractions, per voxel axis (z up). A half-voxel
    shift centres a feature on a voxel column instead of splitting two; 0 keeps the grid
    aligned to the mesh minimum, which is what tiles need so their seams line up. }
  offVX, offVY, offVZ: single;
  { Source up-axis: false means OBJ y is up (the default), true means OBJ z is up. The
    output is always z-up; this says which source axis becomes the height. Kits differ:
    most export y-up, but some (the character rigs) export z-up and would lie down. }
  upZ: boolean;

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
  vx := Trunc((px - bbMin.x) / voxSize + offVX);
  if upZ then begin
    vy := Trunc((py - bbMin.y) / voxSize + offVY);   { obj y -> depth }
    vz := Trunc((pz - bbMin.z) / voxSize + offVZ);   { obj z -> height }
  end else begin
    vy := Trunc((pz - bbMin.z) / voxSize + offVY);   { obj z -> depth }
    vz := Trunc((py - bbMin.y) / voxSize + offVZ);   { obj y -> height }
  end;
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

function Wrap01(v: single): single;
{ Fold a UV coordinate into [0,1), so a texture that tiles beyond the unit square samples
  correctly. }
begin
  Wrap01 := Frac(v);
  if Wrap01 < 0 then Wrap01 := Wrap01 + 1;
end;

function SampleTex(mi: longint; uu, vv: single): byte;
{ The palette index of material mi's texture at (uu, vv). The image row 0 is the top, while
  OBJ v runs bottom-up, so v is flipped. Channels are quantised a little to keep many near
  shades from exhausting the 255-colour palette. }
var
  px, py: longint;
  col: TFPColor;
  r, g, b: byte;
begin
  px := Trunc(Wrap01(uu) * mats[mi].texW);
  py := Trunc((1 - Wrap01(vv)) * mats[mi].texH);
  if px < 0 then px := 0; if px >= mats[mi].texW then px := mats[mi].texW - 1;
  if py < 0 then py := 0; if py >= mats[mi].texH then py := mats[mi].texH - 1;
  col := mats[mi].tex.Colors[px, py];
  r := (col.red shr 8) and $F8;
  g := (col.green shr 8) and $F8;
  b := (col.blue shr 8) and $F8;
  SampleTex := PaletteIndex(r, g, b);
end;

procedure VoxelizeTri(const t: TTri);
var
  v0, v1, v2: TV3;
  uv0, uv1, uv2: TUV;
  e1len, e2len: single;
  steps, i, j: longint;
  u, w, b0: single;
  px, py, pz: single;
  textured: boolean;
  col: byte;
begin
  v0 := verts[t.a]; v1 := verts[t.b]; v2 := verts[t.c];
  textured := (t.mat >= 0) and mats[t.mat].hasTex and
              (t.ua >= 0) and (t.ub >= 0) and (t.uc >= 0);
  if textured then begin
    uv0 := uvs[t.ua]; uv1 := uvs[t.ub]; uv2 := uvs[t.uc];
  end;
  e1len := Dist(v1, v0); e2len := Dist(v2, v0);
  steps := Trunc(2.0 * (e1len + e2len) / voxSize) + 2;
  for i := 0 to steps do
    for j := 0 to steps - i do begin
      u := i / steps;
      w := j / steps;
      px := v0.x + (v1.x - v0.x) * u + (v2.x - v0.x) * w;
      py := v0.y + (v1.y - v0.y) * u + (v2.y - v0.y) * w;
      pz := v0.z + (v1.z - v0.z) * u + (v2.z - v0.z) * w;
      if textured then begin
        b0 := 1 - u - w;
        col := SampleTex(t.mat,
          uv0.u * b0 + uv1.u * u + uv2.u * w,
          uv0.v * b0 + uv1.v * u + uv2.v * w);
      end else
        col := t.colorIdx;
      MarkPoint(px, py, pz, col);
    end;
end;

function ModalColor: byte;
{ The most common non-empty colour in the grid, used to fill the interior so an
  exposed cross-section matches the shell. Falls back to 1 when the grid is empty. }
var
  hist: array[1..255] of longint;
  i, best: longint;
  v: byte;
begin
  for i := 1 to 255 do hist[i] := 0;
  for i := 0 to m.sx * m.sy * m.sz - 1 do begin
    v := m.cells[i];
    if v <> 0 then Inc(hist[v]);
  end;
  best := 1;
  for i := 2 to 255 do
    if hist[i] > hist[best] then best := i;
  ModalColor := best;
end;

procedure SolidFill;
{ Mark the empty voxels reachable from the grid boundary (the outside), then fill
  every empty voxel that was not reached: the interior the shell encloses. }
var
  outside: array of ByteBool;
  stack: array of longint;
  top, idx, nxny, x, y, z, i: longint;
  fillCol: byte;

  procedure Push(ix, iy, iz: longint);
  var k: longint;
  begin
    if (ix < 0) or (iy < 0) or (iz < 0) or
       (ix >= m.sx) or (iy >= m.sy) or (iz >= m.sz) then exit;
    k := ix + iy * m.sx + iz * nxny;
    if outside[k] then exit;
    if m.cells[k] <> 0 then exit;    { a shell voxel stops the flood }
    outside[k] := True;
    stack[top] := k; Inc(top);
  end;

begin
  nxny := m.sx * m.sy;
  SetLength(outside, m.sx * m.sy * m.sz);
  SetLength(stack, m.sx * m.sy * m.sz);
  top := 0;

  { Seed from every empty voxel on the six faces of the grid. }
  for z := 0 to m.sz - 1 do
    for y := 0 to m.sy - 1 do
      for x := 0 to m.sx - 1 do
        if (x = 0) or (y = 0) or (z = 0) or
           (x = m.sx-1) or (y = m.sy-1) or (z = m.sz-1) then
          Push(x, y, z);

  { Flood the outside through empty space, six-connected. }
  while top > 0 do begin
    Dec(top); idx := stack[top];
    z := idx div nxny;
    y := (idx - z * nxny) div m.sx;
    x := idx - z * nxny - y * m.sx;
    Push(x-1, y, z); Push(x+1, y, z);
    Push(x, y-1, z); Push(x, y+1, z);
    Push(x, y, z-1); Push(x, y, z+1);
  end;

  { Any empty voxel the flood never reached is enclosed interior. }
  fillCol := ModalColor;
  for i := 0 to m.sx * m.sy * m.sz - 1 do
    if (m.cells[i] = 0) and (not outside[i]) then m.cells[i] := fillCol;
end;

procedure CropCell(n, ox, oy: longint);
{ Crop the model to one n-wide, n-deep cell (the x and depth axes), full height, so a kit
  module becomes a single tiling cell. A negative offset centres the cut; a depth already
  under n is kept whole. Run after the solid pass so the cut face shows filled interior. }
var
  d: TVoxModel;
  wx, wy, x, y, z: longint;
  v: byte;
begin
  wx := n; if wx > m.sx then wx := m.sx;
  wy := n; if wy > m.sy then wy := m.sy;
  if ox < 0 then ox := (m.sx - wx) div 2;
  if oy < 0 then oy := (m.sy - wy) div 2;
  if ox > m.sx - wx then ox := m.sx - wx;
  if oy > m.sy - wy then oy := m.sy - wy;
  if ox < 0 then ox := 0;
  if oy < 0 then oy := 0;
  VoxAlloc(d, wx, wy, m.sz);
  d.palette := m.palette;
  for z := 0 to m.sz - 1 do
    for y := 0 to wy - 1 do
      for x := 0 to wx - 1 do begin
        v := VoxCell(m, ox + x, oy + y, z);
        if v <> 0 then VoxSetCell(d, x, y, z, v);
      end;
  m := d;
end;

procedure CellFill(n: longint);
{ Extrude a thin sliced piece through the full cell depth so it becomes a solid cell block
  instead of a face panel. For each (x, height) column with any voxel, fill the whole depth
  (0..n-1) with that column's frontmost colour. The silhouette and its colours are kept, so
  a crenellated wall top survives, but rows of these cells form a solid mass rather than
  free-standing fins. Run after the crop. }
var
  d: TVoxModel;
  x, y, z: longint;
  c: byte;
begin
  VoxAlloc(d, m.sx, n, m.sz);
  d.palette := m.palette;
  for z := 0 to m.sz - 1 do
    for x := 0 to m.sx - 1 do begin
      c := 0;
      for y := 0 to m.sy - 1 do begin
        c := VoxCell(m, x, y, z);
        if c <> 0 then break;
      end;
      if c <> 0 then
        for y := 0 to n - 1 do VoxSetCell(d, x, y, z, c);
    end;
  m := d;
end;

function ArgValue(const flag: string): string;
{ The parameter after the first occurrence of flag, or '' when it is absent. }
var k: longint;
begin
  ArgValue := '';
  for k := 1 to ParamCount - 1 do
    if LowerCase(ParamStr(k)) = flag then begin ArgValue := ParamStr(k + 1); exit; end;
end;

procedure ParseOffset(const s: string);
{ "vx,vy,vz" (voxel fractions) into the per-axis phase offset; missing parts stay 0. }
var a, b, idx: longint; parts: array[0..2] of single;
begin
  parts[0] := 0; parts[1] := 0; parts[2] := 0;
  idx := 0; a := 1;
  while (idx < 3) and (a <= Length(s)) do begin
    b := a;
    while (b <= Length(s)) and (s[b] <> ',') do Inc(b);
    parts[idx] := StrToFloatDef(Copy(s, a, b - a), 0);
    Inc(idx); a := b + 1;
  end;
  offVX := parts[0]; offVY := parts[1]; offVZ := parts[2];
end;

var
  res, i: longint;
  ex, ey, ez, maxExt, voxUnits: single;
  nx, ny, nz: longint;
  doSolid, doCellFill: boolean;
  cellN, cellOX, cellOY, p: longint;
  s: string;
begin
  if ParamCount < 2 then begin
    writeln(StdErr, 'usage: voxelize input.obj output.vox [resolution] [surface]');
    writeln(StdErr, '       [--voxel <units-per-voxel>] [--offset <vx,vy,vz>] [--up y|z]');
    writeln(StdErr, '       [--cell <n>] [--celloff <ox,oy>] [--cellfill]');
    halt(2);
  end;
  res := 48;
  if (ParamCount >= 3) and (Copy(ParamStr(3), 1, 2) <> '--') then
    res := StrToIntDef(ParamStr(3), 48);
  if res < 1 then res := 1;
  if res > 255 then res := 255;
  doSolid := True;
  offVX := 0; offVY := 0; offVZ := 0;
  for i := 1 to ParamCount do
    if LowerCase(ParamStr(i)) = 'surface' then doSolid := False;
  voxUnits := StrToFloatDef(ArgValue('--voxel'), 0);
  if ArgValue('--offset') <> '' then ParseOffset(ArgValue('--offset'));
  upZ := LowerCase(ArgValue('--up')) = 'z';
  cellN := StrToIntDef(ArgValue('--cell'), 0);
  doCellFill := False;
  for i := 1 to ParamCount do
    if LowerCase(ParamStr(i)) = '--cellfill' then doCellFill := True;
  cellOX := -1; cellOY := -1;
  s := ArgValue('--celloff');
  if s <> '' then begin
    p := Pos(',', s);
    if p > 0 then begin
      cellOX := StrToIntDef(Copy(s, 1, p - 1), -1);
      cellOY := StrToIntDef(Copy(s, p + 1, Length(s)), -1);
    end;
  end;

  nverts := 0; nuvs := 0; ntris := 0; nmats := 0; npal := 0;
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
  if voxUnits > 0 then voxSize := voxUnits else voxSize := maxExt / res;

  { grid dims: obj x->sx, obj z->sy, obj y->sz; a positive phase offset pushes samples
    toward higher indices, so give that axis one extra voxel of headroom. }
  nx := Trunc(ex / voxSize) + 1; if offVX > 0 then Inc(nx);
  if upZ then begin
    ny := Trunc(ey / voxSize) + 1;   { depth = obj y }
    nz := Trunc(ez / voxSize) + 1;   { height = obj z }
  end else begin
    ny := Trunc(ez / voxSize) + 1;   { depth = obj z }
    nz := Trunc(ey / voxSize) + 1;   { height = obj y }
  end;
  if offVY > 0 then Inc(ny);
  if offVZ > 0 then Inc(nz);
  if nx > 255 then nx := 255;
  if ny > 255 then ny := 255;
  if nz > 255 then nz := 255;
  VoxAlloc(m, nx, ny, nz);

  for i := 0 to ntris - 1 do
    VoxelizeTri(tris[i]);

  if doSolid then SolidFill;
  if cellN > 0 then CropCell(cellN, cellOX, cellOY);
  if doCellFill and (cellN > 0) then CellFill(cellN);

  for i := 1 to 255 do m.palette[i] := palette[i];

  if not VoxSave(ParamStr(2), m) then begin
    writeln(StdErr, 'voxelize: could not write ', ParamStr(2));
    halt(1);
  end;
  writeln('voxelize: ', ParamStr(1), ' -> ', ParamStr(2),
          ' (', m.sx, 'x', m.sy, 'x', m.sz, ', ', VoxSolidCount(m), ' voxels, ',
          npal, ' colours)');
end.
