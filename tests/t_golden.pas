program t_golden;

{** The determinism golden: pins the absolute generated output so a server and every
  client build a byte-identical world from a seed, as multiplayer needs.

  The other generation tests prove a seed reproduces itself. This one proves the output
  itself has not drifted: for a fixed table of (seed, depth) cases it hashes the carved
  and dressed tiles and the emitted brush instances over a fixed block of regions, then
  checks each hash against a stored value.

  CONTENT_VERSION is folded into every hash, so the version stamp and the goldens are
  locked together: changing generation without bumping the version fails the test (the
  hash moved), and bumping the version without updating the goldens fails it too (the
  fold moved the hash). When a change to the output is intended, bump CONTENT_VERSION,
  rerun, and paste the printed hashes below. GL-free and reads no files. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld, brushfield;

const
  { Hashed region block per case: regions (0..SPAN-1) on each axis. 2x2 crosses seams. }
  SPAN = 2;

type
  TCase = record
    Seed:  QWord;
    Depth: LongInt;
    Tiles: QWord;   { expected tile hash }
    Inst:  QWord;   { expected instance hash }
  end;

const
  { Goldens. Regenerate by running this test and pasting the printed values, only when
    the output change is intended and CONTENT_VERSION has been bumped. }
  CASES: array[0..2] of TCase = (
    (Seed: 7;  Depth: 1; Tiles: $E767E9DB73E5D072; Inst: $B57460E35FBD01C5),
    (Seed: 7;  Depth: 5; Tiles: $0991A1AFC2A692FA; Inst: $AF0381F1C7CC921D),
    (Seed: 42; Depth: 3; Tiles: $30BD2A51B23CD269; Inst: $2CB02CF7042FE53D)
  );

  FNV_OFFSET = QWord(14695981039346656037);
  FNV_PRIME  = QWord(1099511628211);

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

procedure HashByte(var h: QWord; b: Byte);
begin
  h := h xor b;
  h := h * FNV_PRIME;
end;

procedure HashInt(var h: QWord; v: LongInt);
var
  u: LongWord;
begin
  u := LongWord(v);
  HashByte(h, u and $FF);
  HashByte(h, (u shr 8) and $FF);
  HashByte(h, (u shr 16) and $FF);
  HashByte(h, (u shr 24) and $FF);
end;

{ Hash the carved and dressed tiles over the region block, in a fixed scan order. }
function HashTiles(var tw: TTileWorld): QWord;
var
  h: QWord;
  rx, ry, lx, ly: LongInt;
begin
  h := FNV_OFFSET;
  HashInt(h, CONTENT_VERSION);
  for ry := 0 to SPAN - 1 do
    for rx := 0 to SPAN - 1 do
      for ly := 0 to REGION - 1 do
        for lx := 0 to REGION - 1 do
          HashByte(h, TileAt(tw, rx * REGION + lx, ry * REGION + ly));
  HashTiles := h;
end;

{ Hash the emitted brush instances over the region block, region by region in the order
  the field itself owns them. }
function HashInsts(var tw: TTileWorld): QWord;
var
  h: QWord;
  rx, ry, k: LongInt;
  list: TBrushList;
begin
  h := FNV_OFFSET;
  HashInt(h, CONTENT_VERSION);
  for ry := 0 to SPAN - 1 do
    for rx := 0 to SPAN - 1 do begin
      BrushEmitRegion(tw, rx, ry, list);
      HashInt(h, list.N);
      for k := 0 to list.N - 1 do begin
        HashByte(h, list.Inst[k].Brush);
        HashInt(h, list.Inst[k].X);
        HashInt(h, list.Inst[k].Y);
        HashByte(h, list.Inst[k].Rot);
      end;
    end;
  HashInsts := h;
end;

var
  i: LongInt;
  tw: TTileWorld;
  ht, hi: QWord;

begin
  fails := 0;
  writeln('  content version ', CONTENT_VERSION);

  for i := 0 to High(CASES) do begin
    TileWorldInit(tw, CASES[i].Seed, CASES[i].Depth);
    ht := HashTiles(tw);
    hi := HashInsts(tw);
    writeln('  seed ', CASES[i].Seed, ' depth ', CASES[i].Depth,
            '  tiles $', HexStr(ht, 16), '  inst $', HexStr(hi, 16));
    Check(ht = CASES[i].Tiles, 'tile hash drifted for this seed and depth');
    Check(hi = CASES[i].Inst, 'instance hash drifted for this seed and depth');
  end;

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' checks failed'); Halt(1); end;
end.
