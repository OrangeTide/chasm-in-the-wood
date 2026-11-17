program t_font;

{** Tests the CFN bitmap-font decoder: a well-formed blob decodes to the right
  metrics and glyph bytes, malformed blobs are rejected, and the shipped
  content/fonts/ui.cfn decodes with its expected ASCII range. GL-free. }

{$mode objfpc}{$H+}

uses
  sysutils, cfnfont;

const
  { A two-glyph font: codes 65..66, cell 2 rows of 1 byte, baseline row 2. }
  SAMPLE: array[0..14] of Byte = (
    Ord('C'), Ord('F'), Ord('N'), Ord('1'),
    2,            { cellH }
    2,            { asc }
    65,           { lo 'A' }
    66,           { hi 'B' }
    1,            { rowBytes }
    5, 6,         { advances }
    $80, $40,     { 'A' rows }
    $C0, $20);    { 'B' rows }

var
  fails: LongInt;
  blob: array[0..14] of Byte;
  i: LongInt;
  f: TCfnFont;
  realBlob: array of Byte;
  stream: File;
  rn: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

begin
  fails := 0;
  for i := 0 to High(SAMPLE) do blob[i] := SAMPLE[i];

  Check(CfnDecode(blob[0], Length(blob), f), 'a well-formed blob decodes');
  Check((f.Lo = 65) and (f.Hi = 66), 'the code range round-trips');
  Check((f.CellH = 2) and (f.Asc = 2) and (f.RowBytes = 1), 'the metrics round-trip');
  Check((f.Adv[0] = 5) and (f.Adv[1] = 6), 'the advances round-trip');
  Check((f.Bits[0] = $80) and (f.Bits[1] = $40), 'glyph A rows round-trip');
  Check((f.Bits[2] = $C0) and (f.Bits[3] = $20), 'glyph B rows round-trip');

  { Too short to hold a header. }
  Check(not CfnDecode(blob[0], 4, f), 'a blob shorter than the header is rejected');

  { Wrong magic. }
  blob[0] := Ord('X');
  Check(not CfnDecode(blob[0], Length(blob), f), 'a bad magic is rejected');
  blob[0] := Ord('C');

  { Declared size larger than the data present. }
  blob[7] := 90;   { hi now 'Z', so the blob is too short for its own tables }
  Check(not CfnDecode(blob[0], Length(blob), f), 'a size mismatch is rejected');
  blob[7] := 66;

  { The shipped font, if present, decodes across printable ASCII. }
  if FileExists('content/fonts/ui.cfn') then begin
    AssignFile(stream, 'content/fonts/ui.cfn');
    Reset(stream, 1);
    rn := FileSize(stream);
    SetLength(realBlob, rn);
    BlockRead(stream, realBlob[0], rn);
    CloseFile(stream);
    Check(CfnDecode(realBlob[0], rn, f), 'content/fonts/ui.cfn decodes');
    Check((f.Lo <= Ord(' ')) and (f.Hi >= Ord('~')), 'ui.cfn covers printable ASCII');
  end;

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
