program t_hero;

{** Tests character creation and progression, GL-free: ability modifiers, species and
  class deriving the starting character, the opening kit, and leveling from experience. }

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

var
  pl: TPlayer;
  human, dwarf, fighter: LongInt;
  sword, larmor, shield, potion: LongInt;
  hp0, max0, lv: LongInt;
begin
  fails := 0;
  Check(ContentLoad('content', c), 'content loaded');
  human   := SpeciesByIdx(c, 'HUMAN');
  dwarf   := SpeciesByIdx(c, 'DWARF');
  fighter := ClassByIdx(c, 'FIGHTER');
  sword   := ItemByIdx(c, 'SWORD');
  larmor  := ItemByIdx(c, 'LARMOR');
  shield  := ItemByIdx(c, 'SHIELD');
  potion  := ItemByIdx(c, 'POTION');
  Check((human >= 0) and (dwarf >= 0) and (fighter >= 0), 'test species and class present');

  { Ability modifiers: two points per step, floored. }
  Check(AbilityMod(10) = 0, 'ten is no modifier');
  Check(AbilityMod(12) = 1, 'twelve is plus one');
  Check(AbilityMod(14) = 2, 'fourteen is plus two');
  Check(AbilityMod(8) = -1, 'eight is minus one');
  Check(AbilityMod(7) = -2, 'seven is minus two');

  { A human fighter: the prime-plus-one species sharpens the class prime, the soldier kit
    is worn, and the derived stats follow. }
  PlayerCreate(pl, c, human, fighter, 'Thorne', 3, 4);
  Check(pl.Name = 'Thorne', 'name set');
  Check((pl.Species = human) and (pl.Klass = fighter), 'species and class recorded');
  Check(pl.Level = 1, 'starts at level one');
  Check(pl.Str = 11, 'human prime-plus-one lifts the fighter strength');
  Check(pl.Equip[eqWeapon] = sword, 'soldier kit wields a sword');
  Check(pl.Equip[eqArmor] = larmor, 'soldier kit wears leather');
  Check(pl.Equip[eqShield] = shield, 'soldier kit carries a shield');
  Check(PackHas(pl, potion), 'every adventurer packs a draught');
  Check(pl.MaxHp = c.Classes[fighter].HitDie + AbilityMod(pl.Con),
        'hit points are the class die plus the constitution modifier');
  Check(pl.Ac = c.Items[larmor].AC + AbilityMod(pl.Dex) + c.Items[shield].AC,
        'armour class folds leather, dexterity, and shield');
  Check(pl.DmgDie = c.Items[sword].Dmg, 'the sword sets the damage die');

  { Species shifts the ability scores. }
  PlayerCreate(pl, c, dwarf, fighter, 'Korrig', 3, 4);
  Check(pl.Con = 11, 'dwarf constitution is raised');
  Check(pl.Cha = 9, 'dwarf charisma is lowered');

  { Leveling: one hundred experience lifts a level-one character to level two and raises
    the hit-point maximum; the remainder is banked toward the next. }
  PlayerCreate(pl, c, human, fighter, 'Thorne', 3, 4);
  max0 := pl.MaxHp;
  lv := PlayerGainXp(pl, c, XpToNext(1) + 50);
  Check(lv = 1, 'a hundred experience grants one level');
  Check(pl.Level = 2, 'the character is level two');
  Check(pl.Xp = 50, 'the surplus experience is banked');
  Check(pl.MaxHp > max0, 'leveling raises the hit-point maximum');

  { Enough for two levels at once. }
  PlayerCreate(pl, c, human, fighter, 'Thorne', 3, 4);
  lv := PlayerGainXp(pl, c, XpToNext(1) + XpToNext(2));
  Check(lv = 2, 'banked experience can grant two levels at once');
  Check(pl.Level = 3, 'the character is level three');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
