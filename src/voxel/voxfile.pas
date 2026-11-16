unit voxfile;

{** MagicaVoxel .vox read and write.

  Stores a model as a dense grid of palette indices (0 = empty) plus its 255-entry
  colour palette, which is the shape the greedy mesher wants. The reader keeps the
  first model in a file and ignores the scene-graph and material chunks; the writer
  emits a Single SIZE/XYZI/RGBA model that MagicaVoxel and this reader both accept.

  Palette indexing follows the format's quirk: a voxel's colour index c in 1..255
  maps to the c-1'th entry of the RGBA chunk. We hide that offset here so the rest
  of the engine just reads palette[c]. }

{$mode objfpc}{$H+}

interface

uses
  sysutils, classes;

type
  TVoxRGBA = packed record
    r, g, b, a: Byte;
  end;

  TVoxModel = record
    sx, sy, sz: LongInt;              { dimensions; z is up, per the format }
    cells: array of Byte;             { dense sx*sy*sz, index x + y*sx + z*sx*sy }
    palette: array[1..255] of TVoxRGBA;
  end;

function VoxCell(const m: TVoxModel; x, y, z: LongInt): Byte; inline;
procedure VoxSetCell(var m: TVoxModel; x, y, z: LongInt; v: Byte); inline;
procedure VoxAlloc(var m: TVoxModel; sx, sy, sz: LongInt);
function VoxSolidCount(const m: TVoxModel): LongInt;

function VoxLoad(const path: String; out m: TVoxModel): Boolean;
function VoxSave(const path: String; const m: TVoxModel): Boolean;

implementation

function VoxCell(const m: TVoxModel; x, y, z: LongInt): Byte;
begin
  if (x < 0) or (y < 0) or (z < 0) or
     (x >= m.sx) or (y >= m.sy) or (z >= m.sz) then
    VoxCell := 0
  else
    VoxCell := m.cells[x + y * m.sx + z * m.sx * m.sy];
end;

procedure VoxSetCell(var m: TVoxModel; x, y, z: LongInt; v: Byte);
begin
  m.cells[x + y * m.sx + z * m.sx * m.sy] := v;
end;

procedure VoxAlloc(var m: TVoxModel; sx, sy, sz: LongInt);
begin
  m.sx := sx; m.sy := sy; m.sz := sz;
  SetLength(m.cells, sx * sy * sz);
  FillChar(m.cells[0], length(m.cells), 0);
end;

function VoxSolidCount(const m: TVoxModel): LongInt;
var
  i, n: LongInt;
begin
  n := 0;
  for i := 0 to length(m.cells) - 1 do
    if m.cells[i] <> 0 then Inc(n);
  VoxSolidCount := n;
end;

{ ---- Reader ---- }

function ReadI32(const buf: array of Byte; pos: LongInt): LongInt; inline;
begin
  { Native little-endian matches the file format. }
  ReadI32 := PInteger(@buf[pos])^;
end;

function TagEq(const buf: array of Byte; pos: LongInt; const tag: String): Boolean;
begin
  TagEq := (buf[pos] = ord(tag[1])) and (buf[pos+1] = ord(tag[2])) and
           (buf[pos+2] = ord(tag[3])) and (buf[pos+3] = ord(tag[4]));
end;

procedure DefaultPalette(var m: TVoxModel);
{ The file carried no RGBA chunk (rare for MagicaVoxel exports). Fall back to a
  neutral grey ramp so geometry is at least visible. }
var
  i: LongInt;
  v: Byte;
begin
  for i := 1 to 255 do begin
    v := 40 + (i * 180) div 255;
    m.palette[i].r := v; m.palette[i].g := v; m.palette[i].b := v;
    m.palette[i].a := 255;
  end;
end;

function VoxLoad(const path: String; out m: TVoxModel): Boolean;
var
  fs: TFileStream;
  buf: array of Byte;
  pos, endPos, n, cn, numVox, i, vi: LongInt;
  haveSize, haveModel, haveRGBA: Boolean;
  psx, psy, psz: LongInt;
  vx, vy, vz, ci: Byte;
begin
  VoxLoad := False;
  haveSize := False; haveModel := False; haveRGBA := False;
  try
    fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
  except
    writeln(StdErr, 'voxfile: cannot open ', path);
    exit;
  end;
  try
    SetLength(buf, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(buf[0], fs.Size);
  finally
    fs.Free;
  end;

  if (length(buf) < 8) or not TagEq(buf, 0, 'VOX ') then begin
    writeln(StdErr, 'voxfile: not a VOX file: ', path);
    exit;
  end;

  { MAIN chunk at offset 8: id(4) contentN(4) childrenN(4) then children. }
  if not TagEq(buf, 8, 'MAIN') then begin
    writeln(StdErr, 'voxfile: missing MAIN chunk: ', path);
    exit;
  end;
  pos := 8 + 12 + ReadI32(buf, 12);        { skip MAIN content (normally 0) }
  endPos := pos + ReadI32(buf, 16);        { children span }
  if endPos > length(buf) then endPos := length(buf);

  while pos + 12 <= endPos do begin
    n  := ReadI32(buf, pos + 4);           { content bytes }
    cn := ReadI32(buf, pos + 8);           { child bytes }
    if TagEq(buf, pos, 'SIZE') then begin
      psx := ReadI32(buf, pos + 12);
      psy := ReadI32(buf, pos + 12 + 4);
      psz := ReadI32(buf, pos + 12 + 8);
      haveSize := True;
    end
    else if TagEq(buf, pos, 'XYZI') and haveSize and not haveModel then begin
      VoxAlloc(m, psx, psy, psz);
      numVox := ReadI32(buf, pos + 12);
      for i := 0 to numVox - 1 do begin
        vi := pos + 12 + 4 + i * 4;
        vx := buf[vi]; vy := buf[vi+1]; vz := buf[vi+2]; ci := buf[vi+3];
        if (vx < psx) and (vy < psy) and (vz < psz) then
          VoxSetCell(m, vx, vy, vz, ci);
      end;
      haveModel := True;
    end
    else if TagEq(buf, pos, 'RGBA') then begin
      for i := 1 to 255 do begin
        vi := pos + 12 + (i - 1) * 4;      { index c maps to entry c-1 }
        m.palette[i].r := buf[vi];
        m.palette[i].g := buf[vi+1];
        m.palette[i].b := buf[vi+2];
        m.palette[i].a := buf[vi+3];
      end;
      haveRGBA := True;
    end;
    pos := pos + 12 + n + cn;
  end;

  if not haveModel then begin
    writeln(StdErr, 'voxfile: no model in ', path);
    exit;
  end;
  if not haveRGBA then DefaultPalette(m);
  VoxLoad := True;
end;

{ ---- Writer ---- }

procedure PutI32(s: TStream; v: LongInt); inline;
begin
  s.WriteBuffer(v, 4);
end;

procedure PutTag(s: TStream; const tag: String); inline;
var
  b: array[0..3] of Byte;
begin
  b[0] := ord(tag[1]); b[1] := ord(tag[2]);
  b[2] := ord(tag[3]); b[3] := ord(tag[4]);
  s.WriteBuffer(b, 4);
end;

procedure PutChunk(s: TStream; const tag: String; content: TMemoryStream);
begin
  PutTag(s, tag);
  PutI32(s, content.Size);
  PutI32(s, 0);                            { no child chunks }
  if content.Size > 0 then
    s.WriteBuffer(content.Memory^, content.Size);
end;

function VoxSave(const path: String; const m: TVoxModel): Boolean;
var
  fs: TFileStream;
  body, c: TMemoryStream;
  x, y, z, i: LongInt;
  v: Byte;
  rgba: TVoxRGBA;
begin
  VoxSave := False;
  body := TMemoryStream.Create;
  c := TMemoryStream.Create;
  try
    { SIZE }
    c.Clear;
    PutI32(c, m.sx); PutI32(c, m.sy); PutI32(c, m.sz);
    PutChunk(body, 'SIZE', c);

    { XYZI }
    c.Clear;
    PutI32(c, VoxSolidCount(m));
    for z := 0 to m.sz - 1 do
      for y := 0 to m.sy - 1 do
        for x := 0 to m.sx - 1 do begin
          v := VoxCell(m, x, y, z);
          if v <> 0 then begin
            c.WriteByte(x); c.WriteByte(y); c.WriteByte(z); c.WriteByte(v);
          end;
        end;
    PutChunk(body, 'XYZI', c);

    { RGBA: entry i holds colour index i+1; last entry unused. }
    c.Clear;
    for i := 0 to 255 do begin
      if i < 255 then rgba := m.palette[i + 1]
      else begin rgba.r := 0; rgba.g := 0; rgba.b := 0; rgba.a := 0; end;
      c.WriteByte(rgba.r); c.WriteByte(rgba.g);
      c.WriteByte(rgba.b); c.WriteByte(rgba.a);
    end;
    PutChunk(body, 'RGBA', c);

    try
      fs := TFileStream.Create(path, fmCreate);
    except
      writeln(StdErr, 'voxfile: cannot write ', path);
      exit;
    end;
    try
      PutTag(fs, 'VOX ');
      PutI32(fs, 150);                     { format version }
      PutTag(fs, 'MAIN');
      PutI32(fs, 0);                       { MAIN has no content }
      PutI32(fs, body.Size);               { all model chunks are its children }
      fs.WriteBuffer(body.Memory^, body.Size);
    finally
      fs.Free;
    end;
    VoxSave := True;
  finally
    c.Free;
    body.Free;
  end;
end;

end.
