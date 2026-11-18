program t_doors;

{** Locked doors: a fraction of a dungeon's doors generate locked, deterministically; the
  town has none; opening one with a key records it, flips the tile to an open door, and
  keeps it open when the region is evicted and regenerated. GL-free. }

{$mode objfpc}{$H+}

uses
  tilemap, tileworld;

var
  fails: LongInt;
  tw: TTileWorld;
  doors1, locked1, locked2, dx, dy: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function CountTiles(var w: TTileWorld; want: Byte; lo, hi: LongInt): LongInt;
var
  x, y, n: LongInt;
begin
  n := 0;
  for y := lo to hi do
    for x := lo to hi do
      if TileAt(w, x, y) = want then Inc(n);
  CountTiles := n;
end;

function FirstTile(var w: TTileWorld; want: Byte; lo, hi: LongInt;
  out fx, fy: LongInt): Boolean;
var
  x, y: LongInt;
begin
  for y := lo to hi do
    for x := lo to hi do
      if TileAt(w, x, y) = want then begin fx := x; fy := y; exit(True); end;
  FirstTile := False;
end;

begin
  fails := 0;
  TileWorldClearOpened;

  { A dungeon depth carries doors, some of them locked. }
  TileWorldInit(tw, 4242, 1);
  doors1 := CountTiles(tw, TILE_DOOR, 0, 95);
  locked1 := CountTiles(tw, TILE_DOOR_LOCKED, 0, 95);
  writeln('  depth 1 over a 96x96 window: ', doors1, ' open, ', locked1, ' locked');
  Check(doors1 > 0, 'some doors remain open');
  Check(locked1 > 0, 'some doors generate locked underground');
  TileWorldFree(tw);

  { Regenerating the same depth reproduces the same locked doors. }
  TileWorldInit(tw, 4242, 1);
  locked2 := CountTiles(tw, TILE_DOOR_LOCKED, 0, 95);
  Check(locked2 = locked1, 'locked doors are deterministic across regeneration');

  { Open the first locked door: it flips to an open door and is recorded. }
  Check(FirstTile(tw, TILE_DOOR_LOCKED, 0, 95, dx, dy), 'found a locked door to open');
  Check(TileWorldOpenDoor(tw, dx, dy), 'opening the locked door succeeds');
  Check(TileAt(tw, dx, dy) = TILE_DOOR, 'the opened door is now an open door');
  Check(TileWorldDoorOpened(1, dx, dy), 'the opened door is recorded');
  Check(not TileWorldOpenDoor(tw, dx, dy), 'opening an open door does nothing');
  TileWorldFree(tw);

  { Regenerate: the opened door stays open, so one fewer door is locked. }
  TileWorldInit(tw, 4242, 1);
  Check(TileAt(tw, dx, dy) = TILE_DOOR, 'the opened door stays open after regeneration');
  Check(CountTiles(tw, TILE_DOOR_LOCKED, 0, 95) = locked1 - 1,
        'one fewer locked door after opening one');
  TileWorldFree(tw);
  TileWorldClearOpened;

  { The surface town has no locked doors. }
  TileWorldInitTown(tw, 4242);
  Check(CountTiles(tw, TILE_DOOR_LOCKED, 0, 95) = 0, 'the town has no locked doors');
  TileWorldFree(tw);

  if fails = 0 then writeln('  ok') else writeln('  ', fails, ' FAILURES');
  if fails <> 0 then Halt(1);
end.
