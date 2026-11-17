program t_combat;

{** Tests real-time melee combat, GL-free. A player's swings wear a monster down to
  death and record the kill; an awake monster in reach wears the player down over time;
  the outcome is deterministic for a fixed seed; a slain monster's room regenerates
  empty; and an awake monster closes the distance to the player across open floor. }

{$mode objfpc}{$H+}

uses
  tileworld, content, player, entities, turns;

var
  fails: LongInt;
  c: TContent;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

procedure MakeMonster(var es: TEntitySet; defIdx, cx, cy, hp, rx, ry, idx: LongInt);
{ A single awake monster centred on (cx, cy), bypassing placement so the scenario is
  fixed. }
begin
  SetLength(es.List, 1);
  es.Count := 1; es.Monsters := 1; es.Props := 0;
  es.List[0].Kind := enMonster;
  es.List[0].Cx := cx; es.List[0].Cy := cy;
  es.List[0].Px := cx + 0.5; es.List[0].Py := cy + 0.5;
  es.List[0].DefIdx := defIdx;
  es.List[0].Size := c.Monsters[defIdx].Size;
  es.List[0].R := 1; es.List[0].G := 1; es.List[0].B := 1;
  es.List[0].OrigRx := rx; es.List[0].OrigRy := ry; es.List[0].OrigIdx := idx;
  es.List[0].MaxHp := hp; es.List[0].Hp := hp;
  es.List[0].AtkCd := 0;
  es.List[0].Bonus := 0;
  es.List[0].Alive := True;
  es.List[0].Awake := True;
end;

procedure MakeChest(var es: TEntitySet; rewardIdx, cx, cy, rx, ry, idx: LongInt);
{ A single locked chest centred on (cx, cy), bypassing placement. }
begin
  SetLength(es.List, 1);
  es.Count := 1; es.Monsters := 0; es.Props := 1;
  es.List[0].Kind := enProp;
  es.List[0].Cx := cx; es.List[0].Cy := cy;
  es.List[0].Px := cx + 0.5; es.List[0].Py := cy + 0.5;
  es.List[0].DefIdx := rewardIdx;
  es.List[0].Size := szSmall;
  es.List[0].R := 0.7; es.List[0].G := 0.45; es.List[0].B := 0.2;
  es.List[0].OrigRx := rx; es.List[0].OrigRy := ry; es.List[0].OrigIdx := idx;
  es.List[0].MaxHp := 0; es.List[0].Hp := 0; es.List[0].Energy := 0;
  es.List[0].Bonus := 0; es.List[0].AtkCd := 0;
  es.List[0].Alive := True;
  es.List[0].Awake := False;
  es.List[0].Locked := True;
  es.List[0].Notified := False;
  es.List[0].Role := 0;
end;

function PackHas(const pl: TPlayer; itemIdx: LongInt): Boolean;
var
  i: LongInt;
begin
  PackHas := False;
  for i := 0 to pl.NCarry - 1 do
    if pl.Carry[i] = itemIdx then exit(True);
end;

function SwingToKill(seed: QWord; ratIdx: LongInt; var tw: TTileWorld): LongInt;
{ Number of ready swings to kill a 6 HP monster beside the player, for a seed. }
var
  es: TEntitySet;
  pl: TPlayer;
  n: LongInt;
begin
  EntitiesClearSlain;
  TurnsSeed(seed);
  PlayerInit(pl, 20, 20);
  MakeMonster(es, ratIdx, 20, 20, 6, 5, 6, 7);   { same tile: within reach }
  n := 0;
  while es.List[0].Alive and (n < 500) do begin
    pl.AtkCd := 0;                                { force each swing ready }
    TurnsPlayerSwing(pl, es, c, tw);
    Inc(n);
  end;
  SwingToKill := n;
end;

var
  tw: TTileWorld;
  es: TEntitySet;
  pl: TPlayer;
  ratIdx, demonIdx, n, sx, sy: LongInt;
  startDist, nowDist: Single;
  k1, k2, potionIdx, keyIdx: LongInt;
begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');
  ratIdx := MonsterByIdx(c, 'RAT');
  demonIdx := MonsterByIdx(c, 'DEMON');
  Check(ratIdx >= 0, 'RAT present');
  Check(demonIdx >= 0, 'DEMON present');

  { A player beats down a monster in reach, which dies and is recorded slain. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearSlain;
  TurnsSeed(42);
  PlayerInit(pl, 20, 20);
  MakeMonster(es, ratIdx, 20, 20, 6, 5, 6, 7);
  n := 0;
  while es.List[0].Alive and (n < 500) do begin
    pl.AtkCd := 0;
    TurnsPlayerSwing(pl, es, c, tw);
    Inc(n);
  end;
  Check(not es.List[0].Alive, 'a monster in reach dies under the player''s swings');
  Check(es.Monsters = 0, 'live monster count drops to zero');
  Check(EntitiesIsSlain(0, 5, 6, 7), 'kill recorded in slain registry');
  Check(EntitiesSlainCount >= 1, 'slain registry non-empty');
  TileWorldFree(tw);

  { A strong, awake monster in reach kills a standing player over time. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearSlain;
  TurnsSeed(7);
  PlayerInit(pl, 20, 20);
  MakeMonster(es, demonIdx, 20, 20, 50, 1, 2, 3);
  n := 0;
  while pl.Alive and (n < 5000) do begin
    TurnsUpdate(pl, es, c, tw, 0.1);
    Inc(n);
  end;
  Check(not pl.Alive, 'a monster in reach can kill the player');
  Check(pl.Hp <= 0, 'dead player has no health left');
  TileWorldFree(tw);

  { Same seed, same fight, same result. }
  TileWorldInit(tw, 1337, 0);
  k1 := SwingToKill(99, ratIdx, tw);
  k2 := SwingToKill(99, ratIdx, tw);
  Check(k1 = k2, 'combat is deterministic for a fixed seed');
  TileWorldFree(tw);

  { A slain monster's room regenerates empty. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearSlain;
  EntitiesBuild(es, c, tw, 0, 0, 1, -9999, -9999);
  Check(es.Monsters > 0, 'a region places monsters to slay');
  for n := 0 to es.Count - 1 do
    if es.List[n].Kind = enMonster then begin
      EntitiesSlay(0, es.List[n].OrigRx, es.List[n].OrigRy, es.List[n].OrigIdx);
      break;
    end;
  k1 := es.Monsters;
  EntitiesBuild(es, c, tw, 0, 0, 1, -9999, -9999);
  Check(es.Monsters = k1 - 1, 'slain monster is absent after regeneration');
  TileWorldFree(tw);

  { An awake monster closes on the player over open floor. }
  TileWorldInit(tw, 1337, 0);
  TurnsSeed(1);
  TileWorldSpawn(tw, sx, sy);
  PlayerInit(pl, sx, sy);
  if TileWorldWalkable(tw, sx + 1, sy) and TileWorldWalkable(tw, sx + 2, sy) and
     TileWorldWalkable(tw, sx + 3, sy) then begin
    EntitiesClearSlain;
    MakeMonster(es, ratIdx, sx + 3, sy, 6, 4, 5, 6);
    startDist := Abs(es.List[0].Px - pl.Px) + Abs(es.List[0].Py - pl.Py);
    for n := 1 to 10 do TurnsUpdate(pl, es, c, tw, 0.1);
    nowDist := Abs(es.List[0].Px - pl.Px) + Abs(es.List[0].Py - pl.Py);
    Check(nowDist < startDist, 'awake monster closes on the player');
  end else
    writeln('  (skipped step test: no open corridor at spawn)');
  TileWorldFree(tw);

  { A locked chest stays shut without a key, speaks only once, then opens for one key,
    yielding its reward and recording itself taken. }
  potionIdx := ItemByIdx(c, 'POTION');
  keyIdx := ItemByIdx(c, 'KEY');
  Check((potionIdx >= 0) and (keyIdx >= 0), 'potion and key present');
  TileWorldInit(tw, 1337, 1);
  EntitiesClearTaken;
  TurnsSeed(3);
  PlayerInit(pl, 20, 20);
  MakeChest(es, potionIdx, 20, 20, 5, 6, 7);
  TurnsAutoPickup(pl, es, c, tw);
  Check(es.List[0].Alive, 'a locked chest stays shut without a key');
  Check(es.Props = 1, 'the shut chest is still counted');
  Check(not PackHas(pl, potionIdx), 'nothing is taken from a locked chest');
  Check(es.List[0].Notified, 'the locked chest has spoken its warning');
  { Give a key; the next approach opens it. }
  Check(PlayerPickup(pl, keyIdx), 'take a key');
  TurnsAutoPickup(pl, es, c, tw);
  Check(not es.List[0].Alive, 'the chest opens once a key is spent');
  Check(es.Props = 0, 'the opened chest is no longer counted');
  Check(PlayerCountKind(pl, c, 'key') = 0, 'the key is spent opening the chest');
  Check(PackHas(pl, potionIdx), 'the chest''s reward is in the pack');
  Check(EntitiesIsTaken(1, 5, 6, 7), 'the opened chest is recorded taken');
  TileWorldFree(tw);

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
