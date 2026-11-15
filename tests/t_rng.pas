program t_rng;

{** Tests the seeded RNG: determinism and output bounds. }

{$mode objfpc}{$H+}

uses
  rng;

var
  fails: longint;

procedure Check(cond: boolean; const msg: string);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  a, b: TRng;
  i, v: longint;
  diverged: boolean;
begin
  fails := 0;

  { Same seed reproduces the same sequence. }
  RngSeed(a, 12345); RngSeed(b, 12345);
  diverged := false;
  for i := 1 to 1000 do
    if RngNext(a) <> RngNext(b) then diverged := true;
  Check(not diverged, 'same seed produced different sequences');

  { Different seeds differ (overwhelmingly likely). }
  RngSeed(a, 1); RngSeed(b, 2);
  Check(RngNext(a) <> RngNext(b), 'different seeds produced the same value');

  { Bounds. }
  RngSeed(a, 999);
  for i := 1 to 10000 do begin
    v := RngBelow(a, 10);
    Check((v >= 0) and (v < 10), 'RngBelow out of range');
    v := RngRange(a, 5, 8);
    Check((v >= 5) and (v <= 8), 'RngRange out of range');
  end;
  Check(RngBelow(a, 1) = 0, 'RngBelow(1) should be 0');
  Check(RngBelow(a, 0) = 0, 'RngBelow(0) should be 0');
  Check(RngRange(a, 7, 7) = 7, 'RngRange(7,7) should be 7');

  if fails = 0 then writeln('  ok') else halt(1);
end.
