program voxpack;

{** Inspect and extract models from a multi-model MagicaVoxel .vox pack.

  A MagicaVoxel source pack holds many models (one SIZE/XYZI pair each), a shared RGBA
  palette, and a scene graph of transform (nTRN), group (nGRP), and shape (nSHP) nodes
  that names each piece. The engine's own reader keeps only the first model, so this
  tool pulls a named piece out into a single-model .vox the engine can load and the
  asset bake can stamp into the world.

  Usage:
    voxpack list <pack.vox>                  list every model: index, size, name
    voxpack get  <pack.vox> <name> <out.vox> write the named model as a lone model
    voxpack get  <pack.vox> #<index> <out>   the same, by model index

  Names come from the transform node directly above each shape node. }

{$mode objfpc}{$H+}

uses
  sysutils, classes, voxfile;

type
  TModelRec = record
    Sx, Sy, Sz: LongInt;
    XyziPos, NumVox: LongInt;   { offset of the XYZI content, voxel count }
  end;
  TNameRec = record
    Name: String;
    ModelId: LongInt;
  end;

var
  buf: array of Byte;
  models: array of TModelRec;
  nModels: LongInt;
  names: array of TNameRec;
  nNames: LongInt;
  palette: array[1..255] of TVoxRGBA;
  haveRGBA: Boolean;

function ReadI32(pos: LongInt): LongInt; inline;
begin
  ReadI32 := PInteger(@buf[pos])^;
end;

function TagEq(pos: LongInt; const tag: String): Boolean;
begin
  TagEq := (buf[pos] = Ord(tag[1])) and (buf[pos+1] = Ord(tag[2])) and
           (buf[pos+2] = Ord(tag[3])) and (buf[pos+3] = Ord(tag[4]));
end;

function LoadFile(const path: String): Boolean;
var
  fs: TFileStream;
begin
  LoadFile := False;
  try
    fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
  except
    writeln(StdErr, 'voxpack: cannot open ', path);
    exit;
  end;
  try
    SetLength(buf, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(buf[0], fs.Size);
  finally
    fs.Free;
  end;
  LoadFile := (Length(buf) >= 8) and TagEq(0, 'VOX ');
  if not LoadFile then writeln(StdErr, 'voxpack: not a VOX file: ', path);
end;

{ ---- dict reader over the buffer ---- }

var
  cur: LongInt;   { a scratch cursor for node parsing }

function RdI32: LongInt;
begin
  RdI32 := ReadI32(cur); Inc(cur, 4);
end;

function RdStr: String;
var
  n, i: LongInt;
begin
  n := RdI32;
  SetLength(RdStr, n);
  for i := 1 to n do RdStr[i] := Chr(buf[cur + i - 1]);
  Inc(cur, n);
end;

function RdDictName: String;
{ Read a DICT, returning the value of "_name" if present, else ''. }
var
  np, i: LongInt;
  k, v: String;
begin
  RdDictName := '';
  np := RdI32;
  for i := 0 to np - 1 do begin
    k := RdStr; v := RdStr;
    if k = '_name' then RdDictName := v;
  end;
end;

procedure SkipDict;
var
  np, i: LongInt;
begin
  np := RdI32;
  for i := 0 to np - 1 do begin RdStr; RdStr; end;
end;

procedure RecordName(const nm: String; modelId: LongInt);
begin
  if nm = '' then exit;
  if nNames >= Length(names) then SetLength(names, (nNames + 1) * 2);
  names[nNames].Name := nm;
  names[nNames].ModelId := modelId;
  Inc(nNames);
end;

{ Transform nodes name shapes. We hold the last transform name seen and attach it to
  the shape node it points at; MagicaVoxel writes the nTRN immediately before its
  child, so a one-slot memory of the pending name is enough in practice. }
var
  pendingName: String;

procedure ParseScene;
var
  pos, endPos, n, cn, nodeId, child, nf, numModels, i, mid, nc: LongInt;
begin
  pos := 8 + 12 + ReadI32(12);
  endPos := pos + ReadI32(16);
  if endPos > Length(buf) then endPos := Length(buf);
  pendingName := '';
  while pos + 12 <= endPos do begin
    n := ReadI32(pos + 4);
    cn := ReadI32(pos + 8);
    if TagEq(pos, 'nTRN') then begin
      cur := pos + 12;
      nodeId := RdI32;
      pendingName := RdDictName;   { node attributes: may hold _name }
      { child, reserved, layer, frames follow, but we only need the name memory. }
    end
    else if TagEq(pos, 'nSHP') then begin
      cur := pos + 12;
      nodeId := RdI32;
      SkipDict;                    { node attributes }
      numModels := RdI32;
      for i := 0 to numModels - 1 do begin
        mid := RdI32;
        SkipDict;                  { per-model attributes }
        if i = 0 then RecordName(pendingName, mid);
      end;
      pendingName := '';
    end
    else if TagEq(pos, 'nGRP') then
      pendingName := '';           { a group clears the pending shape name }
    pos := pos + 12 + n + cn;
  end;
end;

procedure ParseModels;
var
  pos, endPos, n, cn, psx, psy, psz: LongInt;
  haveSize: Boolean;
begin
  pos := 8 + 12 + ReadI32(12);
  endPos := pos + ReadI32(16);
  if endPos > Length(buf) then endPos := Length(buf);
  haveSize := False;
  psx := 0; psy := 0; psz := 0;
  haveRGBA := False;
  while pos + 12 <= endPos do begin
    n := ReadI32(pos + 4);
    cn := ReadI32(pos + 8);
    if TagEq(pos, 'SIZE') then begin
      psx := ReadI32(pos + 12); psy := ReadI32(pos + 16); psz := ReadI32(pos + 20);
      haveSize := True;
    end
    else if TagEq(pos, 'XYZI') and haveSize then begin
      if nModels >= Length(models) then SetLength(models, (nModels + 1) * 2);
      models[nModels].Sx := psx; models[nModels].Sy := psy; models[nModels].Sz := psz;
      models[nModels].NumVox := ReadI32(pos + 12);
      models[nModels].XyziPos := pos + 12 + 4;
      Inc(nModels);
      haveSize := False;
    end
    else if TagEq(pos, 'RGBA') then begin
      for n := 1 to 255 do begin
        palette[n].R := buf[pos + 12 + (n-1)*4];
        palette[n].G := buf[pos + 12 + (n-1)*4 + 1];
        palette[n].B := buf[pos + 12 + (n-1)*4 + 2];
        palette[n].A := buf[pos + 12 + (n-1)*4 + 3];
      end;
      haveRGBA := True;
      cn := 0;   { RGBA has no children; n already covers content }
    end;
    pos := pos + 12 + ReadI32(pos + 4) + ReadI32(pos + 8);
  end;
end;

function NameOf(modelId: LongInt): String;
var
  i: LongInt;
begin
  NameOf := '';
  for i := 0 to nNames - 1 do
    if names[i].ModelId = modelId then exit(names[i].Name);
end;

function FindModel(const sel: String): LongInt;
var
  i, idx: LongInt;
begin
  FindModel := -1;
  if (Length(sel) > 0) and (sel[1] = '#') then begin
    idx := StrToIntDef(Copy(sel, 2, Length(sel)), -1);
    if (idx >= 0) and (idx < nModels) then FindModel := idx;
    exit;
  end;
  for i := 0 to nNames - 1 do
    if names[i].Name = sel then exit(names[i].ModelId);
end;

procedure DoList;
var
  i: LongInt;
begin
  writeln(nModels, ' models, ', nNames, ' named',
          BoolToStr(haveRGBA, ', palette present', ', no palette'));
  for i := 0 to nModels - 1 do
    writeln(Format('%4d  %3dx%3dx%3d  %6d vox  %s',
      [i, models[i].Sx, models[i].Sy, models[i].Sz, models[i].NumVox, NameOf(i)]));
end;

function DoGet(const sel, outPath: String): Boolean;
var
  id, i: LongInt;
  m: TVoxModel;
  vi: LongInt;
  vx, vy, vz, ci: Byte;
begin
  DoGet := False;
  id := FindModel(sel);
  if id < 0 then begin writeln(StdErr, 'voxpack: no model "', sel, '"'); exit; end;
  VoxAlloc(m, models[id].Sx, models[id].Sy, models[id].Sz);
  for i := 0 to models[id].NumVox - 1 do begin
    vi := models[id].XyziPos + i * 4;
    vx := buf[vi]; vy := buf[vi+1]; vz := buf[vi+2]; ci := buf[vi+3];
    if (vx < m.Sx) and (vy < m.Sy) and (vz < m.Sz) then VoxSetCell(m, vx, vy, vz, ci);
  end;
  if haveRGBA then
    for i := 1 to 255 do m.Palette[i] := palette[i];
  DoGet := VoxSave(outPath, m);
  if DoGet then
    writeln('wrote ', outPath, ' (', models[id].Sx, 'x', models[id].Sy, 'x',
            models[id].Sz, ', ', models[id].NumVox, ' voxels, "', NameOf(id), '")');
end;

begin
  if (ParamCount < 2) then begin
    writeln(StdErr, 'usage: voxpack list <pack.vox>');
    writeln(StdErr, '       voxpack get <pack.vox> <name|#index> <out.vox>');
    Halt(2);
  end;
  if not LoadFile(ParamStr(2)) then Halt(1);
  ParseModels;
  ParseScene;
  if ParamStr(1) = 'list' then
    DoList
  else if (ParamStr(1) = 'get') and (ParamCount >= 4) then begin
    if not DoGet(ParamStr(3), ParamStr(4)) then Halt(1);
  end else begin
    writeln(StdErr, 'voxpack: unknown command');
    Halt(2);
  end;
end.
