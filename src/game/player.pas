unit player;

{** The player's position, pack, equipment, and combat stats on the dungeon map.

  The player occupies one tile and moves a tile at a time, blocked by anything not
  walkable (walls, unexcavated rock). Movement queries the streaming tile world, so
  the player can walk into regions that have not been generated yet; the query
  generates them.

  The pack holds loose items by content index. Three of them can be worn: a weapon, a
  suit of armour, and a shield. The worn gear drives the combat stats the turn loop
  reads. Armour sets the armour class outright, a shield adds to it, and the weapon
  sets the damage die and grants a small to-hit bonus. With nothing worn the player
  falls back to the unarmed base. Equipping and unequipping move items between the pack
  and the worn slots and recompute the derived stats; combat never reads the gear
  directly, only the derived Ac, Atk, and DmgDie. }

{$mode objfpc}{$H+}

interface

uses
  tileworld, content;

const
  { Unarmed and unarmoured base, before any worn gear. }
  PLAYER_HP      = 16;
  BASE_AC        = 10;
  BASE_ATK       = 2;
  BASE_DMGDIE    = 3;   { a bare fist strikes for 1..3 }
  EQUIP_ATK_BONUS = 1;  { wielding any weapon steadies the hand }
  MAX_CARRY      = 24;  { items the pack holds }
  ABILITY_BASE   = 10;  { an ability score before species adjustment }
  DEFAULT_HITDIE = 8;   { when the character has no class }

  { Item flag bits (mirrors content/items.txt). }
  ITEM_TWO_HANDED = 1;

type
  { The three worn slots. Everything else rides in the pack. }
  TEquipSlot = (eqWeapon, eqArmor, eqShield);

  TPlayer = record
    Cx, Cy: LongInt;          { the tile under the player, derived from Px,Py }
    Px, Py: Single;           { continuous world position (tile units, TILE = 1) }
    Facing: Single;           { heading in radians, for the model and the compass }
    AtkCd:  Single;           { seconds until the next melee swing is ready }
    Hp, MaxHp: LongInt;
    Ac, Atk, DmgDie, DmgBonus: LongInt;      { derived from gear, abilities, level }
    Alive: Boolean;
    Gold: LongInt;
    Carry: array[0 .. MAX_CARRY - 1] of LongInt;   { content item indices }
    NCarry: LongInt;
    Equip: array[TEquipSlot] of LongInt;     { content item index, or -1 when bare }
    { Identity and progression. }
    Name: String[31];
    Species, Klass, Background: LongInt;      { content indices, or -1 }
    Level, Xp: LongInt;
    Str, Dex, Con, Int, Wis, Cha: LongInt;   { ability scores }
  end;

{ The modifier an ability score grants, floored at the usual two-per-point. }
function AbilityMod(score: LongInt): LongInt;

{ The experience needed to advance from this level to the next. }
function XpToNext(level: LongInt): LongInt;

{ Full new-game init: position, an empty pack, bare hands, full health, and a plain
  level-1 character with average abilities. The starting kit and any species or class
  are handed out separately, by PlayerStartKit or PlayerCreate. }
procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);

{ Make a fresh level-1 character of the given species, class, and background (content
  indices, or -1 for none), with ability scores from the species, hit points from the
  class, and the class's opening kit worn. startGold, when positive, is the coin the
  background's past life brings to the purse. Position and empty state come from
  PlayerInit. }
procedure PlayerCreate(out p: TPlayer; const c: TContent;
  speciesIdx, classIdx, bgIdx, startGold: LongInt;
  const name: String; sx, sy: LongInt);

{ Award experience, advancing levels while enough is banked. Each level raises the
  hit-point maximum. Returns the number of levels gained. }
function PlayerGainXp(var p: TPlayer; const c: TContent; amount: LongInt): LongInt;

{ Hand a fresh character its opening gear: a dagger and a suit of leather, worn. }
procedure PlayerStartKit(var p: TPlayer; const c: TContent);

{ Move the player to a tile without touching stats, for stair travel between depths. }
procedure PlayerPlace(var p: TPlayer; sx, sy: LongInt);

{ Restore the player to full health and life, keeping the purse, pack, and gear, for a
  respawn back in town. }
procedure PlayerRevive(var p: TPlayer);

{ Put an item (a content index) in the pack. False when the pack is full. }
function PlayerPickup(var p: TPlayer; itemIdx: LongInt): Boolean;

{ The worn slot an item of this kind takes, or False when it cannot be worn. }
function ItemEquipSlot(const kind: String; out slot: TEquipSlot): Boolean;

{ Whether the content item (by index) is a two-handed weapon, which leaves no hand for
  a shield. A negative index is not two-handed. }
function ItemTwoHanded(const c: TContent; idx: LongInt): Boolean;

{ Enforce the one-free-hand rule: with a two-handed weapon worn, a worn shield returns
  to the pack. Returns True when it moved the shield, so the caller can refresh a view.
  If the pack is full the shield stays worn, but PlayerRecalc already ignores its bonus. }
function PlayerEnforceHands(var p: TPlayer; const c: TContent): Boolean;

{ Recompute Ac, Atk, and DmgDie from the base and whatever is worn. Call after any
  change to the worn slots. }
procedure PlayerRecalc(var p: TPlayer; const c: TContent);

{ Wear the pack item at carrySlot. Any item already in that worn slot returns to the
  pack. False when the item cannot be worn or the index is out of range. }
function PlayerEquip(var p: TPlayer; const c: TContent; carrySlot: LongInt): Boolean;

{ Take off whatever is worn in slot and return it to the pack. False when the slot is
  empty or the pack is full. }
function PlayerUnequip(var p: TPlayer; const c: TContent; slot: TEquipSlot): Boolean;

{ Drink the first healing potion in the pack. Returns the hit points restored, or -1
  when there is nothing to drink or no wound to mend. }
function PlayerQuaff(var p: TPlayer; const c: TContent): LongInt;

{ Raw one-tile move, blocked by walls. The turn loop uses its own action path; this
  stays for callers that only need position movement. }
procedure PlayerMove(var p: TPlayer; dx, dy: LongInt; var tw: TTileWorld);

implementation

function AbilityMod(score: LongInt): LongInt;
{ Two points per modifier, floored, so a 9 is -1 and an 8 is -1 as well. }
begin
  if score >= ABILITY_BASE then AbilityMod := (score - ABILITY_BASE) div 2
  else AbilityMod := -((ABILITY_BASE - score + 1) div 2);
end;

function XpToNext(level: LongInt): LongInt;
{ A gentle curve: the next level always costs a hundred times the current one. }
begin
  if level < 1 then level := 1;
  XpToNext := level * 100;
end;

procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);
var
  s: TEquipSlot;
begin
  p.Cx := sx;
  p.Cy := sy;
  p.Px := sx + 0.5;
  p.Py := sy + 0.5;
  p.Facing := 0;
  p.AtkCd := 0;
  p.MaxHp := PLAYER_HP;
  p.Hp := PLAYER_HP;
  p.Alive := True;
  p.Gold := 0;
  p.NCarry := 0;
  for s := Low(TEquipSlot) to High(TEquipSlot) do p.Equip[s] := -1;
  { A plain level-1 character with average abilities and no species or class. }
  p.Name := 'Vagrant';
  p.Species := -1;
  p.Klass := -1;
  p.Background := -1;
  p.Level := 1;
  p.Xp := 0;
  p.Str := ABILITY_BASE; p.Dex := ABILITY_BASE; p.Con := ABILITY_BASE;
  p.Int := ABILITY_BASE; p.Wis := ABILITY_BASE; p.Cha := ABILITY_BASE;
  { Bare-handed derived stats; with average abilities these are the plain base. }
  p.Ac := BASE_AC;
  p.Atk := BASE_ATK;
  p.DmgDie := BASE_DMGDIE;
  p.DmgBonus := 0;
end;

procedure PlayerStartKit(var p: TPlayer; const c: TContent);
var
  dagger, leather: LongInt;
begin
  dagger := ItemByIdx(c, 'DAGGER');
  leather := ItemByIdx(c, 'LARMOR');
  if dagger >= 0 then p.Equip[eqWeapon] := dagger;
  if leather >= 0 then p.Equip[eqArmor] := leather;
  PlayerRecalc(p, c);
end;

procedure WearById(var p: TPlayer; const c: TContent; const id: String);
{ Wear an item by id if it fits a worn slot, else drop it in the pack. }
var
  idx: LongInt;
  slot: TEquipSlot;
begin
  idx := ItemByIdx(c, id);
  if idx < 0 then exit;
  if ItemEquipSlot(c.Items[idx].Kind, slot) then p.Equip[slot] := idx
  else PlayerPickup(p, idx);
end;

procedure GiveKit(var p: TPlayer; const c: TContent; const kit: String);
{ The opening gear for a class kit. Every adventurer also carries a healing draught. }
begin
  if kit = 'heavy' then begin
    WearById(p, c, 'GREATAXE'); WearById(p, c, 'MARMOR');
  end else if kit = 'archer' then begin
    WearById(p, c, 'BOW'); WearById(p, c, 'LARMOR');
  end else if kit = 'thief' then begin
    WearById(p, c, 'DAGGER'); WearById(p, c, 'LARMOR');
  end else if kit = 'priest' then begin
    WearById(p, c, 'MACE'); WearById(p, c, 'LARMOR'); WearById(p, c, 'SHIELD');
  end else if kit = 'mage' then begin
    WearById(p, c, 'STAFF');
  end else begin                                   { soldier, or no class }
    WearById(p, c, 'SWORD'); WearById(p, c, 'LARMOR'); WearById(p, c, 'SHIELD');
  end;
  PlayerPickup(p, ItemByIdx(c, 'POTION'));
end;

procedure AddToAbility(var p: TPlayer; const prime: String; delta: LongInt);
{ Raise the named ability. }
begin
  if prime = 'STR' then Inc(p.Str, delta)
  else if prime = 'DEX' then Inc(p.Dex, delta)
  else if prime = 'CON' then Inc(p.Con, delta)
  else if prime = 'INT' then Inc(p.Int, delta)
  else if prime = 'WIS' then Inc(p.Wis, delta)
  else if prime = 'CHA' then Inc(p.Cha, delta);
end;

procedure PlayerCreate(out p: TPlayer; const c: TContent;
  speciesIdx, classIdx, bgIdx, startGold: LongInt;
  const name: String; sx, sy: LongInt);
var
  hd: LongInt;
begin
  PlayerInit(p, sx, sy);
  p.Name := name;
  p.Species := speciesIdx;
  p.Klass := classIdx;
  p.Background := bgIdx;
  if startGold > 0 then p.Gold := startGold;
  { Ability scores: the average base shifted by the species. }
  if speciesIdx >= 0 then begin
    Inc(p.Str, c.Species[speciesIdx].Str);
    Inc(p.Dex, c.Species[speciesIdx].Dex);
    Inc(p.Con, c.Species[speciesIdx].Con);
    Inc(p.Int, c.Species[speciesIdx].Int);
    Inc(p.Wis, c.Species[speciesIdx].Wis);
    Inc(p.Cha, c.Species[speciesIdx].Cha);
    { A 'prime +1' species (human style) sharpens the class's prime ability. }
    if (classIdx >= 0) and ((c.Species[speciesIdx].Flags and 2) <> 0) then
      AddToAbility(p, c.Classes[classIdx].Prime, 1);
  end;
  { Hit points: the class hit die plus the constitution modifier, at least one. }
  hd := DEFAULT_HITDIE;
  if classIdx >= 0 then hd := c.Classes[classIdx].HitDie;
  p.MaxHp := hd + AbilityMod(p.Con);
  if p.MaxHp < 1 then p.MaxHp := 1;
  p.Hp := p.MaxHp;
  { The class's opening kit, worn. }
  if classIdx >= 0 then GiveKit(p, c, c.Classes[classIdx].Kit)
  else GiveKit(p, c, '');
  PlayerRecalc(p, c);
end;

function PlayerGainXp(var p: TPlayer; const c: TContent; amount: LongInt): LongInt;
var
  hd, gain, levels: LongInt;
begin
  levels := 0;
  if amount > 0 then Inc(p.Xp, amount);
  while p.Xp >= XpToNext(p.Level) do begin
    Dec(p.Xp, XpToNext(p.Level));
    Inc(p.Level);
    hd := DEFAULT_HITDIE;
    if p.Klass >= 0 then hd := c.Classes[p.Klass].HitDie;
    gain := hd div 2 + 1 + AbilityMod(p.Con);
    if gain < 1 then gain := 1;
    Inc(p.MaxHp, gain);
    Inc(p.Hp, gain);
    Inc(levels);
  end;
  if levels > 0 then PlayerRecalc(p, c);
  PlayerGainXp := levels;
end;

procedure PlayerPlace(var p: TPlayer; sx, sy: LongInt);
begin
  p.Cx := sx;
  p.Cy := sy;
  p.Px := sx + 0.5;
  p.Py := sy + 0.5;
  p.AtkCd := 0;
end;

procedure PlayerRevive(var p: TPlayer);
begin
  p.Hp := p.MaxHp;
  p.Alive := True;
end;

function PlayerPickup(var p: TPlayer; itemIdx: LongInt): Boolean;
begin
  if p.NCarry >= MAX_CARRY then exit(False);
  p.Carry[p.NCarry] := itemIdx;
  Inc(p.NCarry);
  PlayerPickup := True;
end;

function ItemEquipSlot(const kind: String; out slot: TEquipSlot): Boolean;
begin
  ItemEquipSlot := True;
  if kind = 'weapon' then slot := eqWeapon
  else if kind = 'armor' then slot := eqArmor
  else if kind = 'shield' then slot := eqShield
  else ItemEquipSlot := False;
end;

function ItemTwoHanded(const c: TContent; idx: LongInt): Boolean;
begin
  ItemTwoHanded := (idx >= 0) and ((c.Items[idx].Flags and ITEM_TWO_HANDED) <> 0);
end;

procedure PlayerRecalc(var p: TPlayer; const c: TContent);
{ Fold gear, abilities, and level into the combat stats. Armour sets the base armour
  class and a shield adds to it, dexterity sharpens defence, strength sharpens the blow,
  and the to-hit climbs with level. With average abilities at level 1 and a lone weapon,
  this is the plain base plus the weapon bonus. }
begin
  p.Ac := BASE_AC;
  if p.Equip[eqArmor] >= 0 then
    p.Ac := c.Items[p.Equip[eqArmor]].AC;          { armour sets the class outright }
  Inc(p.Ac, AbilityMod(p.Dex));
  { A shield adds its bonus, but only when a hand is free to hold it: a two-handed
    weapon occupies both, so its shield grants nothing. }
  if (p.Equip[eqShield] >= 0) and not ItemTwoHanded(c, p.Equip[eqWeapon]) then
    Inc(p.Ac, c.Items[p.Equip[eqShield]].AC);

  p.Atk := BASE_ATK + (p.Level - 1) + AbilityMod(p.Str);
  if p.Equip[eqWeapon] >= 0 then Inc(p.Atk, EQUIP_ATK_BONUS);

  if p.Equip[eqWeapon] >= 0 then p.DmgDie := c.Items[p.Equip[eqWeapon]].Dmg
  else p.DmgDie := BASE_DMGDIE;
  p.DmgBonus := AbilityMod(p.Str);
end;

procedure RemoveCarryAt(var p: TPlayer; i: LongInt);
{ Drop pack slot i, closing the gap so the pack stays packed from the front. }
var
  k: LongInt;
begin
  for k := i to p.NCarry - 2 do p.Carry[k] := p.Carry[k + 1];
  Dec(p.NCarry);
end;

function PlayerEnforceHands(var p: TPlayer; const c: TContent): Boolean;
begin
  PlayerEnforceHands := False;
  if ItemTwoHanded(c, p.Equip[eqWeapon]) and (p.Equip[eqShield] >= 0) then
    if PlayerPickup(p, p.Equip[eqShield]) then begin
      p.Equip[eqShield] := -1;
      PlayerEnforceHands := True;
    end;
end;

function PlayerEquip(var p: TPlayer; const c: TContent; carrySlot: LongInt): Boolean;
var
  itemIdx, prev: LongInt;
  slot: TEquipSlot;
  freeOff: Boolean;
begin
  PlayerEquip := False;
  if (carrySlot < 0) or (carrySlot >= p.NCarry) then exit;
  itemIdx := p.Carry[carrySlot];
  if not ItemEquipSlot(c.Items[itemIdx].Kind, slot) then exit;
  { A two-handed weapon and a shield cannot share the hands: wearing one frees the
    other to the pack. That freed item is an extra return, so the pack needs a slot. }
  freeOff := ((slot = eqWeapon) and ItemTwoHanded(c, itemIdx) and (p.Equip[eqShield] >= 0))
          or ((slot = eqShield) and ItemTwoHanded(c, p.Equip[eqWeapon]));
  if freeOff and (p.NCarry >= MAX_CARRY) then exit;   { no room for the freed off-hand }
  prev := p.Equip[slot];
  { Pull the new item out of the pack, then return the displaced one. The base swap is
    size-neutral, so the return always fits. }
  RemoveCarryAt(p, carrySlot);
  if freeOff then
    if slot = eqWeapon then begin
      PlayerPickup(p, p.Equip[eqShield]); p.Equip[eqShield] := -1;
    end else begin
      PlayerPickup(p, p.Equip[eqWeapon]); p.Equip[eqWeapon] := -1;
    end;
  p.Equip[slot] := itemIdx;
  if prev >= 0 then PlayerPickup(p, prev);
  PlayerRecalc(p, c);
  PlayerEquip := True;
end;

function PlayerUnequip(var p: TPlayer; const c: TContent; slot: TEquipSlot): Boolean;
begin
  PlayerUnequip := False;
  if p.Equip[slot] < 0 then exit;
  if not PlayerPickup(p, p.Equip[slot]) then exit;   { pack full: leave it worn }
  p.Equip[slot] := -1;
  PlayerRecalc(p, c);
  PlayerUnequip := True;
end;

function PlayerQuaff(var p: TPlayer; const c: TContent): LongInt;
var
  i, heal: LongInt;
begin
  PlayerQuaff := -1;
  if p.Hp >= p.MaxHp then exit;         { no wound to mend }
  for i := 0 to p.NCarry - 1 do begin
    if c.Items[p.Carry[i]].Kind <> 'potion' then continue;
    { An elixir restores everything; an ordinary draught mends a fixed amount. Holly is
      for reviving a fallen ally, not for drinking, so it is passed over. }
    if c.Items[p.Carry[i]].Id = 'HOLLY' then continue;
    if c.Items[p.Carry[i]].Id = 'ELIXIR' then heal := p.MaxHp
    else heal := 10;
    if p.Hp + heal > p.MaxHp then heal := p.MaxHp - p.Hp;
    Inc(p.Hp, heal);
    RemoveCarryAt(p, i);
    exit(heal);
  end;
end;

procedure PlayerMove(var p: TPlayer; dx, dy: LongInt; var tw: TTileWorld);
begin
  if TileWorldWalkable(tw, p.Cx + dx, p.Cy + dy) then begin
    p.Cx := p.Cx + dx;
    p.Cy := p.Cy + dy;
  end;
end;

end.
