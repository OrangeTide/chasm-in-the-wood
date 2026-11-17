unit cfnfont;
{ The CFN bitmap font: a compact format the GUI canvas renders directly.

  A CFN blob is a header followed by two tables. Every field is a byte, so there
  is nothing to byte-swap. Glyphs cover the contiguous code range Lo..Hi; a glyph
  is CellH rows of RowBytes bytes, and in each row bit 7 is the leftmost column.

    'C' 'F' 'N' '1'
    u8 CellH        rows per glyph cell
    u8 Asc          baseline row from the top of the cell
    u8 Lo, u8 Hi    first and last code point
    u8 RowBytes     bytes per glyph row
    Adv[Lo..Hi]     one advance-width byte per glyph
    Bits[Lo..Hi]    CellH*RowBytes bytes per glyph, rows top to bottom

  The decoder validates the sizes so a short or malformed file is rejected rather
  than read out of bounds. }

{$mode objfpc}{$H+}

interface

type
  TCfnFont = record
    Lo, Hi, CellH, Asc, RowBytes: LongInt;
    Adv:  array of Byte;   { advance width per glyph, indexed code - Lo }
    Bits: array of Byte;   { flat rows: (code-Lo)*CellH*RowBytes + row*RowBytes }
  end;

{ Decode a CFN blob into f. Returns False and leaves f untouched when the blob is
  too short, lacks the magic, or does not match its own declared sizes. }
function CfnDecode(const data; len: LongInt; out f: TCfnFont): Boolean;

implementation

function CfnDecode(const data; len: LongInt; out f: TCfnFont): Boolean;
var
  p: PByte;
  lo, hi, cellH, rowBytes, n, want, i: LongInt;
begin
  CfnDecode := False;
  if len < 9 then exit;
  p := @data;
  if (p[0] <> Ord('C')) or (p[1] <> Ord('F')) or
     (p[2] <> Ord('N')) or (p[3] <> Ord('1')) then exit;
  cellH    := p[4];
  lo       := p[6];
  hi       := p[7];
  rowBytes := p[8];
  if (hi < lo) or (cellH < 1) or (cellH > 64) or
     (rowBytes < 1) or (rowBytes > 4) then exit;
  n := hi - lo + 1;
  want := 9 + n + n * cellH * rowBytes;
  if len <> want then exit;

  f.Lo := lo; f.Hi := hi; f.CellH := cellH; f.Asc := p[5]; f.RowBytes := rowBytes;
  SetLength(f.Adv, n);
  SetLength(f.Bits, n * cellH * rowBytes);
  for i := 0 to n - 1 do f.Adv[i] := p[9 + i];
  for i := 0 to n * cellH * rowBytes - 1 do f.Bits[i] := p[9 + n + i];
  CfnDecode := True;
end;

end.
