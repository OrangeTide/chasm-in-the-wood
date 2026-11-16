program t_town;

{** Tests the town hub and its trade, GL-free. The hamlet is a bounded town tile
  source with a chasm down-stair and walkable spawn; the townsfolk stand on their
  tiles and block the player; the trader buys the pack for coin; the innkeeper trades
  coin for rest; and loot is picked up in the dungeon and stays taken. }

{$mode objfpc}{$H+}

uses
  tilemap, themes, tileworld, town, content, player, entities, townsfolk, turns;

var
  fails: LongInt;
  c: TContent;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  tw: TTileWorld;
  es: TEntitySet;
  pl: TPlayer;
  lay: TTownLayout;
  i, ti, before, expect, pidx: LongInt;
begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');

  { The hamlet: a town tile source with its own theme, a walkable spawn, and the chasm
    as a walkable down-stair. Region (0,0) is the town; far out is solid rock. }
  TileWorldInitTown(tw, 1337);
  Check(TileWorldIsTown(tw), 'world reports as town');
  Check(TileWorldThemeAt(tw, 24, 24) = THEME_TOWN, 'town uses the town theme');
  lay := TileWorldTownLayout(tw);
  Check(TileWorldWalkable(tw, lay.Spawn.X, lay.Spawn.Y), 'spawn is walkable');
  Check(TileAt(tw, lay.Chasm.X, lay.Chasm.Y) = TILE_STAIRS_DOWN, 'chasm is a down-stair');
  Check(TileWorldWalkable(tw, lay.Chasm.X, lay.Chasm.Y), 'chasm is walkable');
  Check(not TileWorldWalkable(tw, 300, 300), 'town is bounded by rock');

  { Townsfolk: four people, on their tiles, blocking the player. }
  TownsfolkBuild(es, lay);
  Check(es.Count = 4, 'four townsfolk placed');
  ti := EntityTownsfolkAt(es, lay.Trader.X, lay.Trader.Y);
  Check(ti >= 0, 'trader stands on the trader tile');
  Check(EntitySolidAt(es, lay.Trader.X, lay.Trader.Y), 'townsperson blocks the tile');
  Check(EntityMonsterAt(es, lay.Trader.X, lay.Trader.Y) < 0,
        'a townsperson is not a monster');

  { The trader buys the whole pack for the sum of the item values. }
  PlayerInit(pl, lay.Trader.X - 1, lay.Trader.Y);
  pl.Carry[0] := 0; pl.Carry[1] := 1; pl.NCarry := 2;
  expect := c.Items[0].Value + c.Items[1].Value;
  Check(TurnsInteract(pl, es, c), 'trader answers when adjacent');
  Check(pl.Gold = expect, 'trader pays the summed value');
  Check(pl.NCarry = 0, 'pack is emptied by the sale');

  { The innkeeper trades coin for a full night's rest. }
  PlayerInit(pl, lay.Innkeeper.X - 1, lay.Innkeeper.Y);
  pl.Hp := 1; pl.Gold := 10;
  Check(TurnsInteract(pl, es, c), 'innkeeper answers when adjacent');
  Check(pl.Hp = pl.MaxHp, 'rest restores full health');
  Check(pl.Gold = 10 - INN_REST_COST, 'rest costs its gold');
  TileWorldFree(tw);

  { Loot pickup in the dungeon: stepping onto a prop takes it, and it stays taken. }
  TileWorldInit(tw, 1337, 0);
  EntitiesClearTaken;
  EntitiesBuild(es, c, tw, 0, 0, 1, -9999, -9999);
  Check(es.Props > 0, 'a region places loot to pick up');
  pidx := -1;
  for i := 0 to es.Count - 1 do
    if (es.List[i].Kind = enProp) and es.List[i].Alive then begin pidx := i; break; end;
  Check(pidx >= 0, 'found a prop to take');
  if pidx >= 0 then begin
    PlayerInit(pl, es.List[pidx].Cx - 1, es.List[pidx].Cy);
    before := es.Props;
    Check(TurnsPlayerAct(pl, es, c, tw, 1, 0), 'stepping onto loot spends a turn');
    Check(pl.NCarry = 1, 'the item is now in the pack');
    Check(es.Props = before - 1, 'the loot count drops');
    Check((pl.Cx = es.List[pidx].Cx) and (pl.Cy = es.List[pidx].Cy),
          'the player stands where the loot was');
  end;
  { Regenerate: the taken prop does not return. }
  EntitiesBuild(es, c, tw, 0, 0, 1, -9999, -9999);
  Check(EntityPropAt(es, pl.Cx, pl.Cy) < 0, 'taken loot stays gone after regeneration');
  TileWorldFree(tw);

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
