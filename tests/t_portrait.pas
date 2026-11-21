program t_portrait;

{** Tests the POR portrait-atlas decoder: a well-formed blob decodes to the right
  directory, sizes, offsets, and bits; names look up case-insensitively; and
  malformed blobs are rejected rather than read out of bounds. GL-free. }

{$mode objfpc}{$H+}

uses
  sysutils, portrait;

const
  { Two 8x2 portraits named FACE0 and FACE1. Layout: header (6) + 2 dir entries
    (12 each) + four bitmap bytes. }
  SAMPLE: array[0..33] of Byte = (
    Ord('P'), Ord('O'), Ord('R'), Ord('1'),
    2, 0,                                              { count = 2, little-endian }
    Ord('F'), Ord('A'), Ord('C'), Ord('E'), Ord('0'), 0, 0, 0,  8, 2, 1, 0,  { FACE0 }
    Ord('F'), Ord('A'), Ord('C'), Ord('E'), Ord('1'), 0, 0, 0,  8, 2, 1, 0,  { FACE1 }
    $80, $01,     { FACE0 rows }
    $FF, $00);    { FACE1 rows }

var
  fails: LongInt;
  blob: array[0..33] of Byte;
  i: LongInt;
  a: TPortraitAtlas;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

begin
  fails := 0;
  for i := 0 to High(SAMPLE) do blob[i] := SAMPLE[i];

  Check(PortraitDecode(blob[0], Length(blob), a), 'a well-formed blob decodes');
  Check(a.Count = 2, 'the count round-trips');
  Check((a.Items[0].Name = 'FACE0') and (a.Items[1].Name = 'FACE1'), 'names round-trip');
  Check((a.Items[0].W = 8) and (a.Items[0].H = 2) and (a.Items[0].RowBytes = 1),
        'the first size round-trips');
  Check((a.Items[0].Ofs = 0) and (a.Items[1].Ofs = 2), 'bit offsets are cumulative');
  Check((a.Bits[0] = $80) and (a.Bits[1] = $01), 'FACE0 rows round-trip');
  Check((a.Bits[2] = $FF) and (a.Bits[3] = $00), 'FACE1 rows round-trip');
  Check(PortraitFind(a, 'face1') = 1, 'lookup is case-insensitive');
  Check(PortraitFind(a, 'nope') = -1, 'an absent name returns -1');

  { Too short to hold the header. }
  Check(not PortraitDecode(blob[0], 4, a), 'a blob shorter than the header is rejected');

  { Wrong magic. }
  blob[0] := Ord('X');
  Check(not PortraitDecode(blob[0], Length(blob), a), 'a bad magic is rejected');
  blob[0] := Ord('P');

  { Declared height larger than the bits present (byte 15 is FACE0's h). }
  blob[15] := 3;
  Check(not PortraitDecode(blob[0], Length(blob), a), 'a size mismatch is rejected');
  blob[15] := 2;

  { rowBytes too small for the declared width (byte 16 is FACE0's rowBytes). }
  blob[16] := 0;
  Check(not PortraitDecode(blob[0], Length(blob), a), 'an undersized rowBytes is rejected');
  blob[16] := 1;

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
