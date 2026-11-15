unit rng;

{** Seeded pseudo-random generator.

  A xorshift64* generator, used instead of the platform RNG so a seed reproduces
  the same world on every host. Small, fast, good enough for level generation. }

{$mode objfpc}{$H+}

interface

type
  TRng = record
    state: qword;
  end;

procedure RngSeed(out r: TRng; seed: qword);
function RngNext(var r: TRng): longword;
function RngBelow(var r: TRng; n: longint): longint;
function RngRange(var r: TRng; lo, hi: longint): longint;

implementation

procedure RngSeed(out r: TRng; seed: qword);
begin
  { Avoid the all-zero state, which xorshift cannot leave. }
  if seed = 0 then seed := qword($9E3779B97F4A7C15);
  r.state := seed;
end;

function RngNext(var r: TRng): longword;
var
  x: qword;
begin
  x := r.state;
  x := x xor (x shr 12);
  x := x xor (x shl 25);
  x := x xor (x shr 27);
  r.state := x;
  RngNext := longword((x * qword($2545F4914F6CDD1D)) shr 32);
end;

function RngBelow(var r: TRng; n: longint): longint;
{ Uniform in [0, n-1]; returns 0 when n <= 1. }
begin
  if n <= 1 then RngBelow := 0
  else RngBelow := longint(RngNext(r) mod longword(n));
end;

function RngRange(var r: TRng; lo, hi: longint): longint;
{ Uniform in [lo, hi] inclusive. }
begin
  if hi <= lo then RngRange := lo
  else RngRange := lo + RngBelow(r, hi - lo + 1);
end;

end.
