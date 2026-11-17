program t_dice;

{** Tests the dice-expression evaluator: constants, dice bounds, precedence of
  multiplication over addition, whitespace, determinism, and malformed input. }

{$mode objfpc}{$H+}

uses
  rng, dice;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  r, r2: TRng;
  v, i, lo, hi: LongInt;
  ok: Boolean;
begin
  fails := 0;
  RngSeed(r, 42);

  { A plain number evaluates to itself and parses. }
  Check((DiceEval('17', r, ok) = 17) and ok, 'plain number');
  Check((DiceEval('0', r, ok) = 0) and ok, 'zero');

  { A product of constants, and precedence: * binds tighter than +. }
  Check((DiceEval('3*4', r, ok) = 12) and ok, 'product');
  Check((DiceEval('2*3+4', r, ok) = 10) and ok, 'mul before add');
  Check((DiceEval('4+2*3', r, ok) = 10) and ok, 'add after mul');
  Check((DiceEval('10-3-2', r, ok) = 5) and ok, 'left-to-right subtraction');

  { Whitespace between tokens is ignored. }
  Check((DiceEval('  5 * 2 + 1 ', r, ok) = 11) and ok, 'whitespace');

  { NdM stays within N..N*M, and a single die within 1..M, across many rolls. }
  for i := 1 to 5000 do begin
    v := DiceEval('2d6', r, ok);
    Check(ok and (v >= 2) and (v <= 12), '2d6 out of range');
    v := DiceEval('1d6', r, ok);
    Check(ok and (v >= 1) and (v <= 6), '1d6 out of range');
  end;

  { "5*2d6" is 5 times a 2..12 roll: in 10..60 and a multiple of 5. }
  for i := 1 to 5000 do begin
    v := DiceEval('5*2d6', r, ok);
    Check(ok and (v >= 10) and (v <= 60) and (v mod 5 = 0), '5*2d6 shape');
  end;

  { "2d6+5" lands in 7..17; "4d6+8" in 12..32. }
  for i := 1 to 5000 do begin
    v := DiceEval('2d6+5', r, ok);
    Check(ok and (v >= 7) and (v <= 17), '2d6+5 range');
    v := DiceEval('4d6+8', r, ok);
    Check(ok and (v >= 12) and (v <= 32), '4d6+8 range');
  end;

  { Zero dice sum to zero. }
  Check((DiceEval('0d6', r, ok) = 0) and ok, '0d6 is zero');

  { Determinism: the same seed drives the same rolls. }
  RngSeed(r, 7); RngSeed(r2, 7);
  Check(DiceEval('3*4d8+2', r, ok) = DiceEval('3*4d8+2', r2, ok),
        'same seed, same roll');

  { Malformed expressions report failure and evaluate to zero. }
  Check((DiceEval('', r, ok) = 0) and (not ok), 'empty string fails');
  Check((DiceEval('2d', r, ok) = 0) and (not ok), 'missing sides fails');
  Check((DiceEval('2d0', r, ok) = 0) and (not ok), 'zero sides fails');
  Check((DiceEval('2+', r, ok) = 0) and (not ok), 'trailing operator fails');
  Check((DiceEval('2d6x', r, ok) = 0) and (not ok), 'trailing garbage fails');

  { A background table expression evaluates (range-check one representative). }
  for i := 1 to 2000 do begin
    v := DiceEval('20*4d6', r, ok);
    lo := 20 * 4; hi := 20 * 24;
    Check(ok and (v >= lo) and (v <= hi), '20*4d6 range');
  end;

  if fails = 0 then writeln('  ok') else halt(1);
end.
