program t_trade;

{** Tests the shop table and the barter logic, GL-free: shops load from shops.txt,
  the trader buys at half value and sells at full, the balance nets Give against Take,
  and a settle moves items and coin. Selling, buying, and bartering are the one model.
  The relic cannot be traded, and a trade that the purse or the pack cannot bear is
  refused. }

{$mode objfpc}{$H+}

uses
  content, player, trade;

var
  fails: LongInt;
  c: TContent;
  pl: TPlayer;
  dagger, sword, potion, relic: LongInt;
  o: TTradeOffer;
  g0: LongInt;
  i: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function PackHas(const p: TPlayer; itemIdx: LongInt): Boolean;
var
  k: LongInt;
begin
  PackHas := False;
  for k := 0 to p.NCarry - 1 do
    if p.Carry[k] = itemIdx then exit(True);
end;

procedure Give(var off: TTradeOffer; const slots: array of LongInt);
var
  k: LongInt;
begin
  SetLength(off.Give, Length(slots));
  for k := 0 to High(slots) do off.Give[k] := slots[k];
end;

procedure Take(var off: TTradeOffer; const items: array of LongInt);
var
  k: LongInt;
begin
  SetLength(off.Take, Length(items));
  for k := 0 to High(items) do off.Take[k] := items[k];
end;

begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');
  dagger := ItemByIdx(c, 'DAGGER');
  sword  := ItemByIdx(c, 'SWORD');
  potion := ItemByIdx(c, 'POTION');
  relic  := ItemByIdx(c, 'RELIC');

  { Shops load from shops.txt. }
  Check(ShopByIdx(c, 'GENERAL') >= 0, 'the GENERAL shop loaded');
  Check(ShopByIdx(c, 'APOTHECARY') >= 0, 'the APOTHECARY shop loaded');
  Check(ShopByIdx(c, 'NOSHOP') < 0, 'an unknown shop is not found');
  Check(Length(c.Shops[ShopByIdx(c, 'APOTHECARY')].Stock) = 3,
        'the apothecary stocks three items');

  { Pricing: buy at full value, sell at half. }
  Check(ItemBuyPrice(c, sword) = 10, 'a sword buys at full value');
  Check(ItemSellPrice(c, sword) = 5, 'a sword sells at half value');
  Check(ItemSellPrice(c, dagger) = 1, 'a cheap item still sells for at least 1');
  Check(not ItemTradable(c, relic), 'the relic is not tradable');

  { Sell only: give the pack, take nothing, gain the sell value. }
  PlayerInit(pl, 0, 0);
  Check(PlayerPickup(pl, dagger), 'carry a dagger');
  Check(PlayerPickup(pl, sword), 'carry a sword');
  pl.Gold := 0;
  Give(o, [0, 1]); Take(o, []);
  Check(TradeBalance(c, pl, o) = 6, 'selling a dagger and a sword nets 6');
  Check(TradeSettle(c, pl, o), 'the sale settles');
  Check((pl.NCarry = 0) and (pl.Gold = 6), 'the pack empties and the purse holds 6');

  { Buy only: empty pack, enough coin, take a potion. }
  PlayerInit(pl, 0, 0);
  pl.Gold := 30;
  Give(o, []); Take(o, [potion]);
  Check(TradeBalance(c, pl, o) = -25, 'buying a potion costs 25');
  Check(TradeSettle(c, pl, o), 'the purchase settles');
  Check(PackHas(pl, potion) and (pl.Gold = 5), 'the potion is in the pack, 5 coin left');

  { Barter: a sword for a dagger, coin settling the spread. }
  PlayerInit(pl, 0, 0);
  Check(PlayerPickup(pl, sword), 'carry a sword');
  pl.Gold := 0;
  g0 := pl.Gold;
  Give(o, [0]); Take(o, [dagger]);
  Check(TradeBalance(c, pl, o) = 3, 'a sword (sell 5) for a dagger (buy 2) nets 3');
  Check(TradeSettle(c, pl, o), 'the barter settles with no coin on hand');
  Check(PackHas(pl, dagger) and not PackHas(pl, sword), 'the dagger replaces the sword');
  Check(pl.Gold = g0 + 3, 'the spread lands in the purse');

  { The relic cannot be offered. }
  PlayerInit(pl, 0, 0);
  Check(PlayerPickup(pl, relic), 'carry the relic');
  Give(o, [0]); Take(o, []);
  Check(not TradeOk(c, pl, o), 'an offer that gives the relic is refused');

  { A purchase beyond the purse is refused. }
  PlayerInit(pl, 0, 0);
  pl.Gold := 0;
  Give(o, []); Take(o, [potion]);
  Check(not TradeOk(c, pl, o), 'buying without the coin is refused');

  { A purchase with no pack room is refused. }
  PlayerInit(pl, 0, 0);
  pl.Gold := 1000;
  for i := 0 to MAX_CARRY - 1 do PlayerPickup(pl, dagger);
  Give(o, []); Take(o, [potion]);
  Check(not TradeOk(c, pl, o), 'buying with a full pack is refused');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
