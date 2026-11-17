program t_entities;

{** Tests the entity spawner: a region window yields entities, every monster is a
  valid content index, and placement is deterministic, so regenerating the world from
  the same seed and depth reproduces the same inhabitants. GL-free. }

{$mode objfpc}{$H+}

uses
  tileworld, content, entities;

var
  fails: LongInt;
  c: TContent;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function FindObjective(const es: TEntitySet): LongInt;
{ The slot of the objective prop, by its reserved identity, or -1. }
var
  i: LongInt;
begin
  FindObjective := -1;
  for i := 0 to es.Count - 1 do
    if (es.List[i].Kind = enProp) and (es.List[i].OrigIdx = OBJECTIVE_IDX) then
      exit(i);
end;

function Same(const a, b: TEntitySet): Boolean;
var
  i: LongInt;
begin
  Same := False;
  if a.Count <> b.Count then exit;
  if (a.Monsters <> b.Monsters) or (a.Props <> b.Props) then exit;
  for i := 0 to a.Count - 1 do begin
    if a.List[i].Kind <> b.List[i].Kind then exit;
    if (a.List[i].Cx <> b.List[i].Cx) or (a.List[i].Cy <> b.List[i].Cy) then exit;
    if a.List[i].DefIdx <> b.List[i].DefIdx then exit;
    if a.List[i].Size <> b.List[i].Size then exit;
    if a.List[i].Locked <> b.List[i].Locked then exit;
  end;
  Same := True;
end;

function PropAvgValueX100(const es: TEntitySet; const c: TContent): LongInt;
{ The average value of the ordinary props (the relic aside), times 100 to keep a
  fraction, or 0 when there are none. }
var
  i, sum, n: LongInt;
begin
  sum := 0; n := 0;
  for i := 0 to es.Count - 1 do
    if (es.List[i].Kind = enProp) and (c.Items[es.List[i].DefIdx].Kind <> 'relic') then
    begin
      Inc(sum, c.Items[es.List[i].DefIdx].Value);
      Inc(n);
    end;
  if n = 0 then PropAvgValueX100 := 0
  else PropAvgValueX100 := (sum * 100) div n;
end;

var
  tw: TTileWorld;
  es1, es2: TEntitySet;
  i, oi, gi, shallowAvg, deepAvg, chests, depth0Chests: LongInt;
  valid: Boolean;
begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');

  { First generation of depth 0 around the origin. }
  TileWorldInit(tw, 1337, 0);
  EntitiesBuild(es1, c, tw, 0, 0, 1, -9999, -9999);
  writeln('  placed ', es1.Count, ' entities (', es1.Monsters, ' foes, ',
          es1.Props, ' props)');
  Check(es1.Count > 0, 'entities placed');
  Check(es1.Monsters > 0, 'some monsters placed');

  { Every monster entity indexes a real monster whose area set was consulted. }
  valid := True;
  for i := 0 to es1.Count - 1 do
    if es1.List[i].Kind = enMonster then
      if (es1.List[i].DefIdx < 0) or (es1.List[i].DefIdx > High(c.Monsters)) then
        valid := False;
  Check(valid, 'monster indices in range');
  TileWorldFree(tw);

  { Regenerate the same world: eviction and re-entry must reproduce placement. }
  TileWorldInit(tw, 1337, 0);
  EntitiesBuild(es2, c, tw, 0, 0, 1, -9999, -9999);
  Check(Same(es1, es2), 'placement is deterministic across regeneration');
  TileWorldFree(tw);

  { The objective sits on the bottom depth, is the relic, and once taken does not
    return when its region regenerates. }
  EntitiesClearTaken;
  TileWorldInit(tw, 1337, DUNGEON_BOTTOM);
  EntitiesBuild(es1, c, tw, 0, 0, 1, -9999, -9999);
  oi := FindObjective(es1);
  Check(oi >= 0, 'the objective is placed on the bottom');
  Check((oi < 0) or (c.Items[es1.List[oi].DefIdx].Kind = 'relic'),
        'the objective is the relic');
  EntitiesTakeProp(DUNGEON_BOTTOM, OBJECTIVE_RX, OBJECTIVE_RY, OBJECTIVE_IDX);
  EntitiesBuild(es2, c, tw, 0, 0, 1, -9999, -9999);
  Check(FindObjective(es2) < 0, 'the taken objective does not return');
  TileWorldFree(tw);
  EntitiesClearTaken;

  { A guardian stands on the bottom, with a boss's bulk, and once slain stays down. }
  EntitiesClearSlain;
  TileWorldInit(tw, 1337, DUNGEON_BOTTOM);
  EntitiesBuild(es1, c, tw, 0, 0, 1, -9999, -9999);
  gi := -1;
  for i := 0 to es1.Count - 1 do
    if (es1.List[i].Kind = enMonster) and (es1.List[i].OrigIdx = GUARDIAN_IDX) then gi := i;
  Check(gi >= 0, 'a guardian stands on the bottom');
  Check((gi < 0) or (es1.List[gi].MaxHp >= 70), 'the guardian has a boss bulk');
  if gi >= 0 then
    EntitiesSlay(DUNGEON_BOTTOM, es1.List[gi].OrigRx, es1.List[gi].OrigRy,
                 es1.List[gi].OrigIdx);
  EntitiesBuild(es2, c, tw, 0, 0, 1, -9999, -9999);
  gi := -1;
  for i := 0 to es2.Count - 1 do
    if (es2.List[i].Kind = enMonster) and (es2.List[i].OrigIdx = GUARDIAN_IDX) then gi := i;
  Check(gi < 0, 'the slain guardian does not return');
  TileWorldFree(tw);
  EntitiesClearSlain;

  { The objective is only at the bottom; a shallower depth has none. }
  TileWorldInit(tw, 1337, 0);
  EntitiesBuild(es1, c, tw, 0, 0, 1, -9999, -9999);
  Check(FindObjective(es1) < 0, 'no objective above the bottom');
  TileWorldFree(tw);

  { Deeper monsters carry a depth bump to their attack. }
  TileWorldInit(tw, 1337, DUNGEON_BOTTOM);
  EntitiesBuild(es1, c, tw, 0, 0, 1, -9999, -9999);
  valid := True;
  for i := 0 to es1.Count - 1 do
    if (es1.List[i].Kind = enMonster) and
       (es1.List[i].OrigIdx <> GUARDIAN_IDX) and
       (es1.List[i].Bonus <> DUNGEON_BOTTOM div 2) then valid := False;
  Check(valid, 'bottom monsters carry the depth attack bump');
  TileWorldFree(tw);

  { Depth-weighted loot: the deeper level yields richer props on average than a shallow
    one over the same wide window. }
  EntitiesClearTaken;
  EntitiesClearSlain;
  TileWorldInit(tw, 1337, 1);
  EntitiesBuild(es1, c, tw, 0, 0, 6, -9999, -9999);
  shallowAvg := PropAvgValueX100(es1, c);
  TileWorldFree(tw);
  TileWorldInit(tw, 1337, DUNGEON_BOTTOM);
  EntitiesBuild(es2, c, tw, 0, 0, 6, -9999, -9999);
  deepAvg := PropAvgValueX100(es2, c);
  TileWorldFree(tw);
  writeln('  loot avg value x100: depth 1 = ', shallowAvg, ', bottom = ', deepAvg,
          ' (', es1.Props, ' vs ', es2.Props, ' props)');
  Check((es1.Props > 5) and (es2.Props > 5), 'enough props to compare');
  Check(deepAvg > shallowAvg, 'deeper loot is richer on average');

  { Keys and locks: an underground build yields locked chests, each holding a real,
    non-key reward; the surface (depth 0) has none. }
  EntitiesClearTaken;
  EntitiesClearSlain;
  TileWorldInit(tw, 1337, 0);
  EntitiesBuild(es1, c, tw, 0, 0, 6, -9999, -9999);
  depth0Chests := 0;
  for i := 0 to es1.Count - 1 do
    if (es1.List[i].Kind = enProp) and es1.List[i].Locked then Inc(depth0Chests);
  TileWorldFree(tw);
  Check(depth0Chests = 0, 'no locked chests on the surface');

  TileWorldInit(tw, 1337, DUNGEON_BOTTOM);
  EntitiesBuild(es1, c, tw, 0, 0, 6, -9999, -9999);
  chests := 0;
  valid := True;
  for i := 0 to es1.Count - 1 do
    if (es1.List[i].Kind = enProp) and es1.List[i].Locked then begin
      Inc(chests);
      if (es1.List[i].DefIdx < 0) or (es1.List[i].DefIdx > High(c.Items)) or
         (c.Items[es1.List[i].DefIdx].Kind = 'key') then valid := False;
    end;
  writeln('  locked chests in a wide bottom build: ', chests);
  Check(chests > 0, 'locked chests appear underground');
  Check(valid, 'each chest holds a real, non-key reward');
  { Deterministic: the same depth and seed reproduce the same chests. }
  EntitiesBuild(es2, c, tw, 0, 0, 6, -9999, -9999);
  Check(Same(es1, es2), 'chest placement is deterministic across regeneration');
  TileWorldFree(tw);

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
