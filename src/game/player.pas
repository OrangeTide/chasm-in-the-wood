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

  { Item flag bits (mirrors content/items.txt). }
  ITEM_TWO_HANDED = 1;

type
  { The three worn slots. Everything else rides in the pack. }
  TEquipSlot = (eqWeapon, eqArmor, eqShield);

  TPlayer = record
    Cx, Cy: LongInt;
    Hp, MaxHp: LongInt;
    Ac, Atk, DmgDie: LongInt;                { derived from the worn gear }
    Alive: Boolean;
    Gold: LongInt;
    Carry: array[0 .. MAX_CARRY - 1] of LongInt;   { content item indices }
    NCarry: LongInt;
    Equip: array[TEquipSlot] of LongInt;     { content item index, or -1 when bare }
  end;

{ Full new-game init: position, an empty pack, bare hands, at full health. The starting
  kit is handed out separately by PlayerStartKit, which needs the content tables. }
procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);

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

procedure PlayerInit(out p: TPlayer; sx, sy: LongInt);
var
  s: TEquipSlot;
begin
  p.Cx := sx;
  p.Cy := sy;
  p.MaxHp := PLAYER_HP;
  p.Hp := PLAYER_HP;
  p.Alive := True;
  p.Gold := 0;
  p.NCarry := 0;
  for s := Low(TEquipSlot) to High(TEquipSlot) do p.Equip[s] := -1;
  { Bare-handed derived stats, without needing the content tables. }
  p.Ac := BASE_AC;
  p.Atk := BASE_ATK;
  p.DmgDie := BASE_DMGDIE;
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

procedure PlayerPlace(var p: TPlayer; sx, sy: LongInt);
begin
  p.Cx := sx;
  p.Cy := sy;
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

procedure PlayerRecalc(var p: TPlayer; const c: TContent);
begin
  p.Ac := BASE_AC;
  p.Atk := BASE_ATK;
  p.DmgDie := BASE_DMGDIE;
  if p.Equip[eqArmor] >= 0 then
    p.Ac := c.Items[p.Equip[eqArmor]].AC;          { armour sets the class outright }
  if p.Equip[eqShield] >= 0 then
    Inc(p.Ac, c.Items[p.Equip[eqShield]].AC);      { a shield adds its bonus }
  if p.Equip[eqWeapon] >= 0 then begin
    p.DmgDie := c.Items[p.Equip[eqWeapon]].Dmg;
    Inc(p.Atk, EQUIP_ATK_BONUS);
  end;
end;

procedure RemoveCarryAt(var p: TPlayer; i: LongInt);
{ Drop pack slot i, closing the gap so the pack stays packed from the front. }
var
  k: LongInt;
begin
  for k := i to p.NCarry - 2 do p.Carry[k] := p.Carry[k + 1];
  Dec(p.NCarry);
end;

function PlayerEquip(var p: TPlayer; const c: TContent; carrySlot: LongInt): Boolean;
var
  itemIdx, prev: LongInt;
  slot: TEquipSlot;
begin
  PlayerEquip := False;
  if (carrySlot < 0) or (carrySlot >= p.NCarry) then exit;
  itemIdx := p.Carry[carrySlot];
  if not ItemEquipSlot(c.Items[itemIdx].Kind, slot) then exit;
  prev := p.Equip[slot];
  { Pull the new item out of the pack, then return the displaced one. Net pack size is
    unchanged, so the return always fits. }
  RemoveCarryAt(p, carrySlot);
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
