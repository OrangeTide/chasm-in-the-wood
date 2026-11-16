program t_combat;

{** Tests the turn loop and melee combat, GL-free. A player attack wears a monster
  down to death and records the kill; an awake monster wears the player down; the
  outcome is deterministic for a fixed seed; a slain monster's room regenerates empty;
  and an awake monster steps toward the player across open floor. }

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
{ A single awake monster at (cx, cy), bypassing placement so the scenario is fixed. }
begin
  SetLength(es.List, 1);
  es.Count := 1; es.Monsters := 1; es.Props := 0;
  es.List[0].Kind := enMonster;
  es.List[0].Cx := cx; es.List[0].Cy := cy;
  es.List[0].DefIdx := defIdx;
  es.List[0].Size := c.Monsters[defIdx].Size;
  es.List[0].R := 1; es.List[0].G := 1; es.List[0].B := 1;
  es.List[0].OrigRx := rx; es.List[0].OrigRy := ry; es.List[0].OrigIdx := idx;
  es.List[0].MaxHp := hp; es.List[0].Hp := hp;
  es.List[0].Energy := 0;
  es.List[0].Bonus := 0;
  es.List[0].Alive := True;
  es.List[0].Awake := True;
end;

function KillCost(seed: QWord; ratIdx: LongInt; var tw: TTileWorld): LongInt;
{ Number of player actions to kill a 6 HP monster beside the player, for a seed. }
var
  es: TEntitySet;
  pl: TPlayer;
  n: LongInt;
begin
  EntitiesClearSlain;
  TurnsSeed(seed);
  PlayerInit(pl, 20, 20);
  MakeMonster(es, ratIdx, 21, 20, 6, 5, 6, 7);
  n := 0;
  while es.List[0].Alive and (n < 500) do begin
    TurnsPlayerAct(pl, es, c, tw, 1, 0);
    Inc(n);
  end;
  KillCost := n;
end;

var
  tw: TTileWorld;
  es: TEntitySet;
  pl: TPlayer;
  ratIdx, demonIdx, n, sx, sy, startDist: LongInt;
  k1, k2: LongInt;
begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');
  ratIdx := MonsterByIdx(c, 'RAT');
  demonIdx := MonsterByIdx(c, 'DEMON');
  Check(ratIdx >= 0, 'RAT present');
  Check(demonIdx >= 0, 'DEMON present');

  { A player beats down an adjacent monster, which dies and is recorded slain. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearSlain;
  TurnsSeed(42);
  PlayerInit(pl, 20, 20);
  MakeMonster(es, ratIdx, 21, 20, 6, 5, 6, 7);
  n := 0;
  while es.List[0].Alive and (n < 500) do begin
    TurnsPlayerAct(pl, es, c, tw, 1, 0);
    Inc(n);
  end;
  Check(not es.List[0].Alive, 'adjacent monster dies under attack');
  Check(es.Monsters = 0, 'live monster count drops to zero');
  Check(EntitiesIsSlain(0, 5, 6, 7), 'kill recorded in slain registry');
  Check(EntitiesSlainCount >= 1, 'slain registry non-empty');
  TileWorldFree(tw);

  { A strong, awake monster beside a standing player kills the player in time. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearSlain;
  TurnsSeed(7);
  PlayerInit(pl, 20, 20);
  MakeMonster(es, demonIdx, 21, 20, 50, 1, 2, 3);
  n := 0;
  while pl.Alive and (n < 2000) do begin
    TurnsRunMonsters(pl, es, c, tw);
    Inc(n);
  end;
  Check(not pl.Alive, 'adjacent monster can kill the player');
  Check(pl.Hp <= 0, 'dead player has no health left');
  TileWorldFree(tw);

  { Same seed, same fight, same result. }
  TileWorldInit(tw, 1337, 0);
  k1 := KillCost(99, ratIdx, tw);
  k2 := KillCost(99, ratIdx, tw);
  Check(k1 = k2, 'combat is deterministic for a fixed seed');
  TileWorldFree(tw);

  { A slain monster's room regenerates empty. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearSlain;
  EntitiesBuild(es, c, tw, 0, 0, 1, -9999, -9999);
  Check(es.Monsters > 0, 'a region places monsters to slay');
  { Slay the first monster by its identity, rebuild, and confirm it is gone. }
  for n := 0 to es.Count - 1 do
    if es.List[n].Kind = enMonster then begin
      EntitiesSlay(0, es.List[n].OrigRx, es.List[n].OrigRy, es.List[n].OrigIdx);
      break;
    end;
  k1 := es.Monsters;
  EntitiesBuild(es, c, tw, 0, 0, 1, -9999, -9999);
  Check(es.Monsters = k1 - 1, 'slain monster is absent after regeneration');
  TileWorldFree(tw);

  { An awake monster steps toward the player over open floor. }
  TileWorldInit(tw, 1337, 0);
  TurnsSeed(1);
  TileWorldSpawn(tw, sx, sy);
  PlayerInit(pl, sx, sy);
  if TileWorldWalkable(tw, sx + 1, sy) and TileWorldWalkable(tw, sx + 2, sy) and
     TileWorldWalkable(tw, sx + 3, sy) then begin
    EntitiesClearSlain;
    MakeMonster(es, ratIdx, sx + 3, sy, 6, 4, 5, 6);
    startDist := Abs(es.List[0].Cx - pl.Cx) + Abs(es.List[0].Cy - pl.Cy);
    { Two player turns give even a slow monster at least one action. }
    for n := 1 to 2 do TurnsRunMonsters(pl, es, c, tw);
    Check(Abs(es.List[0].Cx - pl.Cx) + Abs(es.List[0].Cy - pl.Cy) < startDist,
          'awake monster closes on the player');
  end else
    writeln('  (skipped step test: no open corridor at spawn)');
  TileWorldFree(tw);

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
