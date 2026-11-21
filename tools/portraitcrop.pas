program portraitcrop;
{ Cook a 1-bit portrait atlas (.por, see src/gui/portrait.pas and
  docs/formats/portraits.md) from one or more source sheets, driven by a small
  manifest. This is the portrait counterpart to the voxel pipeline: it owns the
  sheet-cutting so the build needs no ImageMagick step.

  Usage:  portraitcrop <manifest> <out.por>

  Manifest lines (whitespace separated, '#' starts a comment):
    sheet <path>                     set the current source image
    threshold <0..255>               luminance cut for ink (default 128)
    portrait <NAME> <x> <y> <w> <h>  cut one named portrait from the sheet
    grid <PREFIX> <x0> <y0> <w> <h> <cols> <rows>
                                     cut a cols by rows grid, naming cells
                                     PREFIX0, PREFIX1, ... left to right, top row
                                     first

  A pixel becomes ink when it is opaque (alpha >= 128) and darker than the
  threshold, so dark art on either a transparent or a light background cooks the
  same. Names are upper-cased and truncated to 8 characters. The tool ships no
  art; the sheet is supplied at cook time. }

{$mode objfpc}{$H+}

uses
  sysutils, classes, FPImage, FPReadPNG;

type
  TCrop = record
    Name:           String;
    W, H, RowBytes: LongInt;
    Bits:           array of Byte;
  end;

var
  gImg:    TFPMemoryImage;
  gThresh: LongInt = 128;
  crops:   array of TCrop;

{ True when the source pixel at (x, y) is ink: opaque and darker than gThresh. }
function Ink(x, y: LongInt): Boolean;
var
  c: TFPColor;
  r, g, b, a, lum: LongInt;
begin
  Ink := False;
  if (gImg = nil) or (x < 0) or (y < 0) or (x >= gImg.Width) or (y >= gImg.Height) then
    exit;
  c := gImg.Colors[x, y];
  a := c.Alpha shr 8;
  if a < 128 then exit;
  r := c.Red shr 8; g := c.Green shr 8; b := c.Blue shr 8;
  lum := (r * 77 + g * 150 + b * 29) shr 8;
  Ink := lum < gThresh;
end;

{ Cut a w by h portrait whose top-left is (sx, sy) in the current sheet and append
  it to crops under name. }
procedure Cut(const name: String; sx, sy, w, h: LongInt);
var
  i, row, col, rb: LongInt;
  nm: String;
begin
  if gImg = nil then begin
    writeln(StdErr, 'portraitcrop: portrait before any sheet'); halt(1);
  end;
  if (w < 1) or (h < 1) or (w > 255) or (h > 255) then begin
    writeln(StdErr, 'portraitcrop: bad size ', w, 'x', h, ' for ', name); halt(1);
  end;
  rb := (w + 7) div 8;
  nm := UpperCase(name);
  if Length(nm) > 8 then nm := Copy(nm, 1, 8);
  i := Length(crops);
  SetLength(crops, i + 1);
  crops[i].Name := nm;
  crops[i].W := w; crops[i].H := h; crops[i].RowBytes := rb;
  SetLength(crops[i].Bits, h * rb);
  FillChar(crops[i].Bits[0], h * rb, 0);
  for row := 0 to h - 1 do
    for col := 0 to w - 1 do
      if Ink(sx + col, sy + row) then
        crops[i].Bits[row * rb + (col div 8)] :=
          crops[i].Bits[row * rb + (col div 8)] or (128 shr (col mod 8));
end;

procedure LoadSheet(const path: String);
begin
  if gImg <> nil then FreeAndNil(gImg);
  gImg := TFPMemoryImage.Create(0, 0);
  try
    gImg.LoadFromFile(path);
  except
    on e: Exception do begin
      writeln(StdErr, 'portraitcrop: cannot read sheet ', path, ': ', e.Message);
      halt(1);
    end;
  end;
end;

{ Split a line into whitespace-separated tokens, dropping a trailing comment. }
procedure Tokenize(const line: String; out tok: array of String; out n: LongInt);
var
  i, len: LongInt;
  cur: String;
begin
  n := 0; cur := '';
  len := Length(line);
  for i := 1 to len do begin
    if line[i] = '#' then break;
    if line[i] in [' ', #9, #13, #10] then begin
      if cur <> '' then begin
        if n <= High(tok) then tok[n] := cur;
        Inc(n); cur := '';
      end;
    end else
      cur := cur + line[i];
  end;
  if cur <> '' then begin
    if n <= High(tok) then tok[n] := cur;
    Inc(n);
  end;
end;

procedure RunManifest(const path: String);
var
  f: TextFile;
  line: String;
  tok: array[0..7] of String;
  n, lineno, c, r, cols, rows, x0, y0, w, h: LongInt;
begin
  AssignFile(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then begin
    writeln(StdErr, 'portraitcrop: cannot open manifest ', path); halt(1);
  end;
  lineno := 0;
  while not Eof(f) do begin
    ReadLn(f, line);
    Inc(lineno);
    Tokenize(line, tok, n);
    if n = 0 then continue;
    if tok[0] = 'sheet' then begin
      if n < 2 then begin writeln(StdErr, 'portraitcrop:', lineno, ': sheet needs a path'); halt(1); end;
      LoadSheet(tok[1]);
    end else if tok[0] = 'threshold' then begin
      if n < 2 then begin writeln(StdErr, 'portraitcrop:', lineno, ': threshold needs a value'); halt(1); end;
      gThresh := StrToIntDef(tok[1], 128);
    end else if tok[0] = 'portrait' then begin
      if n < 6 then begin writeln(StdErr, 'portraitcrop:', lineno, ': portrait NAME x y w h'); halt(1); end;
      Cut(tok[1], StrToInt(tok[2]), StrToInt(tok[3]), StrToInt(tok[4]), StrToInt(tok[5]));
    end else if tok[0] = 'grid' then begin
      if n < 8 then begin writeln(StdErr, 'portraitcrop:', lineno, ': grid PREFIX x0 y0 w h cols rows'); halt(1); end;
      x0 := StrToInt(tok[2]); y0 := StrToInt(tok[3]);
      w := StrToInt(tok[4]); h := StrToInt(tok[5]);
      cols := StrToInt(tok[6]); rows := StrToInt(tok[7]);
      for r := 0 to rows - 1 do
        for c := 0 to cols - 1 do
          Cut(tok[1] + IntToStr(r * cols + c), x0 + c * w, y0 + r * h, w, h);
    end else begin
      writeln(StdErr, 'portraitcrop:', lineno, ': unknown directive ', tok[0]); halt(1);
    end;
  end;
  CloseFile(f);
end;

procedure WriteAtlas(const path: String);
var
  fs: TFileStream;
  i, k: LongInt;
  hdr: array[0..3] of Byte;
  ent: array[0..11] of Byte;
  nm: String;
begin
  if Length(crops) = 0 then begin
    writeln(StdErr, 'portraitcrop: no portraits to write'); halt(1);
  end;
  if Length(crops) > 65535 then begin
    writeln(StdErr, 'portraitcrop: too many portraits (', Length(crops), ')'); halt(1);
  end;
  fs := TFileStream.Create(path, fmCreate);
  try
    hdr[0] := Ord('P'); hdr[1] := Ord('O'); hdr[2] := Ord('R'); hdr[3] := Ord('1');
    fs.WriteBuffer(hdr[0], 4);
    ent[0] := Length(crops) and $FF; ent[1] := (Length(crops) shr 8) and $FF;
    fs.WriteBuffer(ent[0], 2);
    for i := 0 to High(crops) do begin
      FillChar(ent[0], 12, 0);
      nm := crops[i].Name;
      for k := 1 to Length(nm) do ent[k - 1] := Ord(nm[k]);
      ent[8]  := crops[i].W;
      ent[9]  := crops[i].H;
      ent[10] := crops[i].RowBytes;
      ent[11] := 0;
      fs.WriteBuffer(ent[0], 12);
    end;
    for i := 0 to High(crops) do
      fs.WriteBuffer(crops[i].Bits[0], Length(crops[i].Bits));
  finally
    fs.Free;
  end;
  writeln('portraitcrop: ', Length(crops), ' portraits -> ', path);
end;

begin
  if ParamCount < 2 then begin
    writeln(StdErr, 'usage: portraitcrop <manifest> <out.por>');
    halt(1);
  end;
  RunManifest(ParamStr(1));
  WriteAtlas(ParamStr(2));
  if gImg <> nil then gImg.Free;
end.
