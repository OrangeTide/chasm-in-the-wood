unit dice;

{** Evaluate a small dice expression against a seeded RNG.

  The grammar is a sum of products of integer and NdM dice terms, as the
  background table uses for starting coin: "5*2d6", "2d6+5", "4d6+8", "2d6*3",
  or a plain number. Multiplication binds tighter than addition, and both run
  left to right. Whitespace between tokens is ignored.

  A term "NdM" rolls N dice of M sides and sums them, each die in 1..M drawn
  from the RNG. A malformed expression evaluates to 0 and reports ok False. }

{$mode objfpc}{$H+}

interface

uses
  rng;

{ Evaluate expr, rolling any dice with r. Returns the total; ok reports whether
  the whole string parsed as a valid expression. }
function DiceEval(const expr: String; var r: TRng; out ok: Boolean): LongInt;

implementation

function DiceEval(const expr: String; var r: TRng; out ok: Boolean): LongInt;
var
  s: String;
  pos, len: LongInt;
  good: Boolean;

  procedure SkipSpace;
  begin
    while (pos <= len) and ((s[pos] = ' ') or (s[pos] = #9)) do Inc(pos);
  end;

  function AtDigit: Boolean;
  begin
    AtDigit := (pos <= len) and (s[pos] >= '0') and (s[pos] <= '9');
  end;

  function ParseInt: LongInt;
  var
    v: LongInt;
  begin
    v := 0;
    if not AtDigit then begin good := False; exit(0); end;
    while AtDigit do begin
      v := v * 10 + (Ord(s[pos]) - Ord('0'));
      Inc(pos);
    end;
    ParseInt := v;
  end;

  function Factor: LongInt;
  { A plain integer, or NdM which rolls N dice of M sides and sums them. }
  var
    n, sides, i, total: LongInt;
  begin
    SkipSpace;
    n := ParseInt;
    SkipSpace;
    if (pos <= len) and ((s[pos] = 'd') or (s[pos] = 'D')) then begin
      Inc(pos);
      SkipSpace;
      sides := ParseInt;
      if sides < 1 then begin good := False; exit(0); end;
      total := 0;
      for i := 1 to n do total := total + RngRange(r, 1, sides);
      Factor := total;
    end else
      Factor := n;
  end;

  function Product: LongInt;
  var
    v: LongInt;
  begin
    v := Factor;
    SkipSpace;
    while (pos <= len) and (s[pos] = '*') do begin
      Inc(pos);
      v := v * Factor;
      SkipSpace;
    end;
    Product := v;
  end;

  function Sum: LongInt;
  var
    v: LongInt;
  begin
    v := Product;
    SkipSpace;
    while (pos <= len) and ((s[pos] = '+') or (s[pos] = '-')) do begin
      if s[pos] = '+' then begin Inc(pos); v := v + Product; end
      else begin Inc(pos); v := v - Product; end;
      SkipSpace;
    end;
    Sum := v;
  end;

begin
  s := expr;
  len := Length(s);
  pos := 1;
  good := True;
  DiceEval := Sum;
  SkipSpace;
  if pos <= len then good := False;    { trailing characters that did not parse }
  ok := good;
  if not good then DiceEval := 0;
end;

end.
