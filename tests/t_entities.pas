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
  end;
  Same := True;
end;

var
  tw: TTileWorld;
  es1, es2: TEntitySet;
  i: LongInt;
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

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
