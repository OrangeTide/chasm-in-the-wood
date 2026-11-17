unit trade;

{** Bartering with a town shop. One trade window stages two piles: the items the
  player hands over (Give, by pack slot) and the items taken from the shop (Take, by
  content index). Coin settles the difference, so the one model covers selling (Give
  only), buying (Take only), and barter (both). The trader buys low and sells high: it
  pays half an item's value and charges full value, and that spread is its margin.

  The balance is the net coin to the player, the sell value of Give minus the buy value
  of Take; a negative balance is what the player pays. A trade settles only when every
  item is valid and tradable, the player can cover a payment, and the pack has room for
  the net change. The relic is never tradable. This unit is GL-free and holds no state;
  the window drives it. }

{$mode objfpc}{$H+}

interface

uses
  content, player;

type
  TTradeOffer = record
    Give: array of LongInt;   { pack slot indices the player hands over }
    Take: array of LongInt;   { content item indices taken from the shop }
  end;

{ The price the trader charges the player to take one of its items (full value). }
function ItemBuyPrice(const c: TContent; itemIdx: LongInt): LongInt;

{ The price the trader pays the player for one item (half value, floored, at least 1
  for an item of any value). }
function ItemSellPrice(const c: TContent; itemIdx: LongInt): LongInt;

{ Whether an item may be traded at all. The relic never can. }
function ItemTradable(const c: TContent; itemIdx: LongInt): Boolean;

{ Net coin to the player for the offer: the sell value of Give minus the buy value of
  Take. Negative means the player pays that much. }
function TradeBalance(const c: TContent; const pl: TPlayer;
  const o: TTradeOffer): LongInt;

{ Whether the offer can be settled: the Give slots are valid, distinct, and tradable,
  the Take indices are valid items, the player can cover a payment, and the pack has
  room for the net item change. }
function TradeOk(const c: TContent; const pl: TPlayer;
  const o: TTradeOffer): Boolean;

{ Apply the offer: remove the given items from the pack, add the taken items, and move
  the balance into or out of the purse. Returns False and changes nothing when the
  offer does not pass TradeOk. }
function TradeSettle(const c: TContent; var pl: TPlayer;
  const o: TTradeOffer): Boolean;

implementation

function ItemBuyPrice(const c: TContent; itemIdx: LongInt): LongInt;
begin
  if (itemIdx < 0) or (itemIdx > High(c.Items)) then exit(0);
  ItemBuyPrice := c.Items[itemIdx].Value;
end;

function ItemSellPrice(const c: TContent; itemIdx: LongInt): LongInt;
var
  v: LongInt;
begin
  if (itemIdx < 0) or (itemIdx > High(c.Items)) then exit(0);
  v := c.Items[itemIdx].Value;
  if v <= 0 then exit(0);
  ItemSellPrice := v div 2;
  if ItemSellPrice < 1 then ItemSellPrice := 1;
end;

function ItemTradable(const c: TContent; itemIdx: LongInt): Boolean;
begin
  if (itemIdx < 0) or (itemIdx > High(c.Items)) then exit(False);
  ItemTradable := c.Items[itemIdx].Kind <> 'relic';
end;

function TradeBalance(const c: TContent; const pl: TPlayer;
  const o: TTradeOffer): LongInt;
var
  i, slot, bal: LongInt;
begin
  bal := 0;
  for i := 0 to High(o.Give) do begin
    slot := o.Give[i];
    if (slot >= 0) and (slot < pl.NCarry) then
      Inc(bal, ItemSellPrice(c, pl.Carry[slot]));
  end;
  for i := 0 to High(o.Take) do
    Dec(bal, ItemBuyPrice(c, o.Take[i]));
  TradeBalance := bal;
end;

function TradeOk(const c: TContent; const pl: TPlayer;
  const o: TTradeOffer): Boolean;
var
  i, j, slot, finalCount: LongInt;
begin
  TradeOk := False;
  { Give slots: in range, distinct, and tradable. }
  for i := 0 to High(o.Give) do begin
    slot := o.Give[i];
    if (slot < 0) or (slot >= pl.NCarry) then exit;
    if not ItemTradable(c, pl.Carry[slot]) then exit;
    for j := 0 to i - 1 do
      if o.Give[j] = slot then exit;
  end;
  { Take items: valid content indices and tradable. }
  for i := 0 to High(o.Take) do
    if not ItemTradable(c, o.Take[i]) then exit;
  { The pack must hold the net change. }
  finalCount := pl.NCarry - Length(o.Give) + Length(o.Take);
  if (finalCount < 0) or (finalCount > MAX_CARRY) then exit;
  { A payment must be covered by the purse. }
  if pl.Gold + TradeBalance(c, pl, o) < 0 then exit;
  TradeOk := True;
end;

function TradeSettle(const c: TContent; var pl: TPlayer;
  const o: TTradeOffer): Boolean;
var
  i, slot, w, bal: LongInt;
  drop: array[0 .. MAX_CARRY - 1] of Boolean;
  kept: array[0 .. MAX_CARRY - 1] of LongInt;
  nkept: LongInt;
begin
  TradeSettle := False;
  if not TradeOk(c, pl, o) then exit;
  bal := TradeBalance(c, pl, o);

  { Remove the given pack slots by rebuilding the pack without them. }
  for i := 0 to MAX_CARRY - 1 do drop[i] := False;
  for i := 0 to High(o.Give) do drop[o.Give[i]] := True;
  nkept := 0;
  for i := 0 to pl.NCarry - 1 do
    if not drop[i] then begin
      kept[nkept] := pl.Carry[i];
      Inc(nkept);
    end;
  for i := 0 to nkept - 1 do pl.Carry[i] := kept[i];
  pl.NCarry := nkept;

  { Add the taken items. TradeOk guaranteed the room. }
  for i := 0 to High(o.Take) do begin
    w := pl.NCarry;
    pl.Carry[w] := o.Take[i];
    Inc(pl.NCarry);
  end;

  Inc(pl.Gold, bal);
  TradeSettle := True;
end;

end.
