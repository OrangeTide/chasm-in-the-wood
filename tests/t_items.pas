program t_items;

{** Tests the item model, GL-free: worn gear drives the derived combat stats, equipping
  swaps the displaced item back to the pack, unequipping returns gear to the pack, and a
  healing draught mends a wound and is spent. }

{$mode objfpc}{$H+}

uses
  content, player;

var
  fails: LongInt;
  c: TContent;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function PackHas(const p: TPlayer; itemIdx: LongInt): Boolean;
var
  i: LongInt;
begin
  PackHas := False;
  for i := 0 to p.NCarry - 1 do
    if p.Carry[i] = itemIdx then exit(True);
end;

function FindPack(const p: TPlayer; itemIdx: LongInt): LongInt;
{ The pack slot holding itemIdx, or -1. }
var
  i: LongInt;
begin
  FindPack := -1;
  for i := 0 to p.NCarry - 1 do
    if p.Carry[i] = itemIdx then exit(i);
end;

var
  pl: TPlayer;
  slot: TEquipSlot;
  dagger, sword, leather, chain, shield, potion, elixir, greataxe: LongInt;
  n0, acWithShield: LongInt;
begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');
  dagger  := ItemByIdx(c, 'DAGGER');
  sword   := ItemByIdx(c, 'SWORD');
  leather := ItemByIdx(c, 'LARMOR');
  chain   := ItemByIdx(c, 'MARMOR');
  shield  := ItemByIdx(c, 'SHIELD');
  potion  := ItemByIdx(c, 'POTION');
  elixir  := ItemByIdx(c, 'ELIXIR');
  Check((dagger >= 0) and (sword >= 0) and (leather >= 0) and (chain >= 0) and
        (shield >= 0) and (potion >= 0) and (elixir >= 0), 'test items present');

  { Kind maps to the right worn slot, and non-wearables are refused. }
  Check(ItemEquipSlot('weapon', slot) and (slot = eqWeapon), 'weapon maps to hand');
  Check(ItemEquipSlot('armor', slot) and (slot = eqArmor), 'armor maps to body');
  Check(ItemEquipSlot('shield', slot) and (slot = eqShield), 'shield maps to arm');
  Check(not ItemEquipSlot('potion', slot), 'a potion is not worn');

  { Bare hands: the unarmed base. }
  PlayerInit(pl, 0, 0);
  Check((pl.Ac = BASE_AC) and (pl.Atk = BASE_ATK) and (pl.DmgDie = BASE_DMGDIE),
        'bare hands use the base stats');

  { The opening kit: a dagger and leather, worn, drive the stats. }
  PlayerStartKit(pl, c);
  Check(pl.Equip[eqWeapon] = dagger, 'start kit wields the dagger');
  Check(pl.Equip[eqArmor] = leather, 'start kit wears the leather');
  Check(pl.Ac = c.Items[leather].AC, 'leather sets the armour class');
  Check(pl.DmgDie = c.Items[dagger].Dmg, 'the dagger sets the damage die');
  Check(pl.Atk = BASE_ATK + EQUIP_ATK_BONUS, 'a wielded weapon steadies the hand');

  { Equip a better weapon from the pack; the dagger it displaces returns to the pack. }
  Check(PlayerPickup(pl, sword), 'pick up a sword');
  Check(PlayerEquip(pl, c, pl.NCarry - 1), 'equip the sword from the pack');
  Check(pl.Equip[eqWeapon] = sword, 'the sword is now wielded');
  Check(PackHas(pl, dagger), 'the displaced dagger went back to the pack');
  Check(pl.DmgDie = c.Items[sword].Dmg, 'the sword sets a bigger damage die');

  { A shield adds to the armour class; heavier armour sets a higher base. }
  Check(PlayerPickup(pl, shield), 'pick up a shield');
  Check(PlayerEquip(pl, c, pl.NCarry - 1), 'equip the shield');
  Check(pl.Ac = c.Items[leather].AC + c.Items[shield].AC, 'the shield adds its bonus');
  Check(PlayerPickup(pl, chain), 'pick up chain mail');
  Check(PlayerEquip(pl, c, pl.NCarry - 1), 'equip the chain mail');
  Check(pl.Ac = c.Items[chain].AC + c.Items[shield].AC, 'chain plus shield armour class');

  { Unequip returns the gear to the pack and drops its contribution. }
  Check(PlayerUnequip(pl, c, eqShield), 'take off the shield');
  Check(pl.Equip[eqShield] = -1, 'the shield slot is empty');
  Check(PackHas(pl, shield), 'the shield is back in the pack');
  Check(pl.Ac = c.Items[chain].AC, 'the armour class drops without the shield');

  { A two-handed weapon bars a shield: wielding one frees the other to the pack, and no
    shield bonus applies while it is wielded. }
  greataxe := ItemByIdx(c, 'GREATAXE');
  Check(greataxe >= 0, 'greataxe present');
  Check(ItemTwoHanded(c, greataxe), 'the greataxe reads as two-handed');
  Check(not ItemTwoHanded(c, sword), 'the sword is one-handed');
  { Wear the shield again (sword still wielded), then wield the greataxe. }
  Check(PlayerEquip(pl, c, FindPack(pl, shield)), 'wear the shield again');
  acWithShield := pl.Ac;
  Check(pl.Ac = c.Items[chain].AC + c.Items[shield].AC, 'shield bonus is back');
  Check(PlayerPickup(pl, greataxe), 'pick up the greataxe');
  Check(PlayerEquip(pl, c, FindPack(pl, greataxe)), 'wield the greataxe');
  Check(pl.Equip[eqWeapon] = greataxe, 'the greataxe is wielded');
  Check(pl.Equip[eqShield] = -1, 'the shield was bumped off');
  Check(PackHas(pl, shield), 'the bumped shield is in the pack');
  Check(pl.Ac = acWithShield - c.Items[shield].AC, 'no shield bonus while two-handed');
  { Strapping the shield back on while two-handed bumps the weapon instead. }
  Check(PlayerEquip(pl, c, FindPack(pl, shield)), 'wear the shield over the greataxe');
  Check(pl.Equip[eqShield] = shield, 'the shield is worn');
  Check(pl.Equip[eqWeapon] = -1, 'the two-handed weapon was bumped off');
  Check(PackHas(pl, greataxe), 'the bumped greataxe is in the pack');
  { Put the sword back for the rest of the checks. }
  Check(PlayerEquip(pl, c, FindPack(pl, sword)), 're-wield the sword');

  { A draught mends a wound and is spent; a full pool has nothing to drink for. }
  pl.Hp := pl.MaxHp;
  Check(PlayerQuaff(pl, c) = -1, 'no draught is drunk at full health');
  pl.Hp := 5;
  Check(PlayerPickup(pl, potion), 'pick up a healing potion');
  n0 := pl.NCarry;
  Check(PlayerQuaff(pl, c) = 10, 'the draught restores ten');
  Check(pl.Hp = 15, 'the wound is partly mended');
  Check(pl.NCarry = n0 - 1, 'the potion is spent');

  { An elixir restores the pool to full, capped at the maximum. }
  pl.Hp := 5;
  Check(PlayerPickup(pl, elixir), 'pick up an elixir');
  Check(PlayerQuaff(pl, c) = pl.MaxHp - 5, 'the elixir restores to full');
  Check(pl.Hp = pl.MaxHp, 'health is full after the elixir');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
