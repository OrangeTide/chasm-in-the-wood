unit portrait;
{ The POR portrait atlas: a set of 1-bit portraits the GUI canvas draws through
  the same monochrome bitmap path as the CFN font. This unit is the format and
  its loader only; it carries no art. A sheet is cooked into a .por atlas by
  tools/portraitcrop, and the game maps a speaker or character to a portrait and
  draws it with TCanvas.DrawBitmap.

  A POR blob is a header, a directory, then the packed bitmaps:

    'P' 'O' 'R' '1'
    u16 count              number of portraits, little-endian
    directory: count entries of 12 bytes each
      char[8] name         uppercase, NUL-padded (may be all NUL)
      u8 w, u8 h           portrait size in pixels
      u8 rowBytes          bytes per row, = (w + 7) div 8
      u8 flags             reserved, zero
    bitmaps: every portrait's rows, in directory order, back to back.
      each is h*rowBytes bytes, one bit per pixel, bit 7 the leftmost column;
      a set bit is ink (drawn), a clear bit is transparent.

  Portraits may differ in size within one atlas. The decoder validates every
  size against the blob length, so a short or malformed file is rejected rather
  than read out of bounds. }

{$mode objfpc}{$H+}

interface

type
  TPortrait = record
    Name:           String;   { directory name, trailing NULs trimmed }
    W, H, RowBytes: LongInt;
    Ofs:            LongInt;   { byte offset into Bits where this portrait starts }
  end;

  TPortraitAtlas = record
    Count: LongInt;
    Items: array of TPortrait;
    Bits:  array of Byte;      { every portrait's rows concatenated, index order }
  end;

const
  POR_DIRENT = 12;             { bytes per directory entry }
  POR_HEADER = 6;             { magic (4) + count (2) }

{ Decode a POR blob into a. Returns False and leaves a untouched when the blob is
  too short, lacks the magic, or does not match its own declared sizes. }
function PortraitDecode(const data; len: LongInt; out a: TPortraitAtlas): Boolean;

{ Load a POR file from disk. False on any read or decode failure. }
function PortraitLoad(const path: String; out a: TPortraitAtlas): Boolean;

{ Index of the portrait named n (case-insensitive), or -1 when absent. }
function PortraitFind(const a: TPortraitAtlas; const n: String): LongInt;

implementation

uses sysutils, classes;

function PortraitDecode(const data; len: LongInt; out a: TPortraitAtlas): Boolean;
var
  p: PByte;
  count, i, c, w, h, rb, dirBytes, pixBytes, ent: LongInt;
  nm: String;
begin
  PortraitDecode := False;
  if len < POR_HEADER then exit;
  p := @data;
  if (p[0] <> Ord('P')) or (p[1] <> Ord('O')) or
     (p[2] <> Ord('R')) or (p[3] <> Ord('1')) then exit;
  count := p[4] or (p[5] shl 8);
  if count < 0 then exit;
  dirBytes := count * POR_DIRENT;
  if len < POR_HEADER + dirBytes then exit;

  { First pass: total the bitmap bytes and reject an impossible size. }
  pixBytes := 0;
  for i := 0 to count - 1 do begin
    ent := POR_HEADER + i * POR_DIRENT;
    w  := p[ent + 8];
    h  := p[ent + 9];
    rb := p[ent + 10];
    if (w < 1) or (h < 1) or (rb < (w + 7) div 8) or (rb > 32) then exit;
    pixBytes := pixBytes + h * rb;
  end;
  if len <> POR_HEADER + dirBytes + pixBytes then exit;

  { Second pass: fill the records and copy the bits. }
  a.Count := count;
  SetLength(a.Items, count);
  SetLength(a.Bits, pixBytes);
  ent := 0;   { running offset into Bits }
  for i := 0 to count - 1 do begin
    c := POR_HEADER + i * POR_DIRENT;
    nm := '';
    for w := 0 to 7 do
      if p[c + w] <> 0 then nm := nm + Chr(p[c + w]);
    a.Items[i].Name     := nm;
    a.Items[i].W        := p[c + 8];
    a.Items[i].H        := p[c + 9];
    a.Items[i].RowBytes := p[c + 10];
    a.Items[i].Ofs      := ent;
    ent := ent + a.Items[i].H * a.Items[i].RowBytes;
  end;
  if pixBytes > 0 then
    Move(p[POR_HEADER + dirBytes], a.Bits[0], pixBytes);
  PortraitDecode := True;
end;

function PortraitLoad(const path: String; out a: TPortraitAtlas): Boolean;
var
  fs:  TFileStream;
  buf: array of Byte;
  n:   LongInt;
begin
  PortraitLoad := False;
  if not FileExists(path) then exit;
  try
    fs := TFileStream.Create(path, fmOpenRead);
    try
      n := fs.Size;
      if n <= 0 then exit;
      SetLength(buf, n);
      fs.ReadBuffer(buf[0], n);
    finally
      fs.Free;
    end;
  except
    exit;
  end;
  PortraitLoad := PortraitDecode(buf[0], n, a);
end;

function PortraitFind(const a: TPortraitAtlas; const n: String): LongInt;
var
  i: LongInt;
begin
  for i := 0 to a.Count - 1 do
    if CompareText(a.Items[i].Name, n) = 0 then exit(i);
  PortraitFind := -1;
end;

end.
