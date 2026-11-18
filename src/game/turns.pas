unit turns;
{ Real-time movement and melee combat. The world advances every frame by a time step:  }
{ monsters that have sighted the player chase them across open floor and strike when     }
{ they close to melee range, each on its own attack cooldown, and a faster monster both }
{ moves and swings more often. The player swings on command, hitting the nearest foe    }
{ in reach, and gathers loot it walks over. Death is resolved here: a slain monster is   }
{ recorded so its room stays empty, and a slain player is marked for the caller to       }
{ respawn. Combat is reported through a small log.                                       }

{$mode objfpc}{$H+}

interface

uses
  sysutils, math, tilemap, tileworld, content, player, entities, townsfolk, rng,
  uitext, sfx;

const
  PLAYER_MOVE    = 4.0;   { player speed, tiles per second }
  MON_MOVE_BASE  = 0.55;  { monster speed per point of its content speed, tiles/sec }
  MELEE_RANGE    = 0.95;  { how close, in tiles, a melee strike reaches }
  PLAYER_SWING_CD = 0.45; { seconds between the player's swings }
  MON_SWING_CD    = 1.1;  { seconds between a monster's swings }
  PICKUP_RANGE   = 0.6;   { how close, in tiles, the player gathers loot }
  BODY_RADIUS    = 0.3;   { collision radius for the player and monsters, tiles }
  SIGHT          = 10;    { tiles within which a monster can sight the player }

{ Seed the combat RNG. Combat is not required to reproduce, but a fixed seed makes
  tests and screenshots repeatable. }
procedure TurnsSeed(seed: QWord);

{ True when a body of BODY_RADIUS centred at (wx,wy) stands clear of walls. }
function TurnsPosFree(var tw: TTileWorld; wx, wy: Single): Boolean;

{ Advance the world by dt seconds: cool the player's swing, and chase and strike with
  every awake monster. }
procedure TurnsUpdate(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; dt: Single);

{ The player swings: if a swing is ready and a monster is within reach, strike the
  nearest one and start the cooldown. }
procedure TurnsPlayerSwing(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld);

{ Gather any loot within reach of the player. }
procedure TurnsAutoPickup(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld);

{ The role of a townsperson on a tile adjacent to the player, or -1 when none is there.
  Lets the caller open the trade window for the trader before falling back to speech. }
function TurnsAdjacentRole(const pl: TPlayer; const es: TEntitySet): LongInt;

{ Speak to a townsperson on an adjacent tile, trading with the trader or resting at the
  inn. Returns True when someone was there to answer. }
function TurnsInteract(var pl: TPlayer; var es: TEntitySet; const c: TContent): Boolean;

{ Combat log, oldest kept entry first. }
function TurnsLogCount: LongInt;
function TurnsLogLine(i: LongInt): String;
procedure TurnsLogClear;

{ Append a line to the log, for messages from outside combat (save and load). }
procedure TurnsLogAdd(const s: String);

implementation

const
  LOG_MAX = 8;
  { Sound effects for the actions of the loop, played through the audio unit (silent when
    the file is absent). }
  SFX_SWING  = 'content/sfx/swing.ogg';
  SFX_HIT    = 'content/sfx/hit.ogg';
  SFX_HURT   = 'content/sfx/hurt.ogg';
  SFX_PICKUP = 'content/sfx/pickup.ogg';

var
  gRng:  TRng;
  gLog:  array[0 .. LOG_MAX - 1] of String;
  gLogN: LongInt = 0;        { entries held, capped at LOG_MAX }

procedure TurnsSeed(seed: QWord);
begin
  RngSeed(gRng, seed);
end;

procedure Log(const s: String);
var
  i: LongInt;
begin
  if gLogN < LOG_MAX then begin
    gLog[gLogN] := s;
    Inc(gLogN);
  end else begin
    for i := 1 to LOG_MAX - 1 do gLog[i - 1] := gLog[i];
    gLog[LOG_MAX - 1] := s;
  end;
end;

function TurnsLogCount: LongInt;
begin
  TurnsLogCount := gLogN;
end;

function TurnsLogLine(i: LongInt): String;
begin
  if (i >= 0) and (i < gLogN) then TurnsLogLine := gLog[i]
  else TurnsLogLine := '';
end;

procedure TurnsLogClear;
begin
  gLogN := 0;
end;

procedure TurnsLogAdd(const s: String);
begin
  Log(s);
end;

{ ---- dice ---- }

function Die(n: LongInt): LongInt;
begin
  if n < 1 then n := 1;
  Die := RngRange(gRng, 1, n);
end;

function AttackHits(atk, ac: LongInt): Boolean;
{ A d20 roll plus the to-hit bonus meets the target's ascending armour class. }
begin
  AttackHits := (RngRange(gRng, 1, 20) + atk) >= ac;
end;

function SignOf(v: LongInt): LongInt;
begin
  if v > 0 then SignOf := 1
  else if v < 0 then SignOf := -1
  else SignOf := 0;
end;

{ ---- line of sight ---- }

function Opaque(var tw: TTileWorld; x, y: LongInt): Boolean;
var
  t: Byte;
begin
  t := TileAt(tw, x, y);
  Opaque := (t = TILE_WALL) or (t = TILE_ROCK);
end;

function HasLOS(var tw: TTileWorld; x0, y0, x1, y1, range: LongInt): Boolean;
{ A Bresenham line from the monster to the player: clear when no opaque tile lies
  strictly between them, and only out to range tiles. }
var
  dx, dy, sx, sy, err, e2, x, y: LongInt;
begin
  dx := Abs(x1 - x0);
  dy := Abs(y1 - y0);
  if (dx > range) or (dy > range) then exit(False);
  sx := SignOf(x1 - x0);
  sy := SignOf(y1 - y0);
  err := dx - dy;
  x := x0; y := y0;
  while True do begin
    if (x = x1) and (y = y1) then exit(True);
    e2 := 2 * err;
    if e2 > -dy then begin err := err - dy; x := x + sx; end;
    if e2 <  dx then begin err := err + dx; y := y + sy; end;
    if (x = x1) and (y = y1) then exit(True);
    if Opaque(tw, x, y) then exit(False);
  end;
  HasLOS := False;
end;

{ ---- combat ---- }

procedure KillMonster(var es: TEntitySet; mi: LongInt; const def: TMonsterDef;
  depth: LongInt);
begin
  es.List[mi].Alive := False;
  Dec(es.Monsters);
  EntitiesSlay(depth, es.List[mi].OrigRx, es.List[mi].OrigRy, es.List[mi].OrigIdx);
  Log(def.Name + ' dies.');
end;

procedure PlayerAttack(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; mi: LongInt);
var
  def: TMonsterDef;
  dmg, levels: LongInt;
begin
  def := c.Monsters[es.List[mi].DefIdx];
  es.List[mi].Awake := True;
  if AttackHits(pl.Atk, def.AC) then begin
    dmg := Die(pl.DmgDie) + pl.DmgBonus;
    if dmg < 1 then dmg := 1;
    Dec(es.List[mi].Hp, dmg);
    PlaySfx(SFX_HIT);
    Log(UIStrFmt('msg_hit', [def.Name, dmg]));
    if es.List[mi].Hp <= 0 then begin
      KillMonster(es, mi, def, TileWorldDepth(tw));
      levels := PlayerGainXp(pl, c, def.XP);
      if levels > 0 then Log(UIStrFmt('msg_levelup', [pl.Level]));
    end;
  end else
    Log(UIStrFmt('msg_miss', [def.Name]));
end;

procedure MonsterAttack(var pl: TPlayer; const def: TMonsterDef; bonus: LongInt);
var
  dmg: LongInt;
begin
  if AttackHits(def.Atk + bonus, pl.Ac) then begin
    dmg := Die(def.Dmg) + bonus;
    Dec(pl.Hp, dmg);
    PlaySfx(SFX_HURT);
    Log(UIStrFmt('msg_monster_hit', [def.Name, dmg]));
    if pl.Hp <= 0 then begin
      pl.Hp := 0;
      pl.Alive := False;
      Log(UIStr('msg_die'));
    end;
  end else
    Log(def.Name + ' misses you.');
end;

function TurnsPosFree(var tw: TTileWorld; wx, wy: Single): Boolean;
{ A body clears walls when all four corners of its bounding box lie on walkable tiles. }
  function Open(x, y: Single): Boolean;
  begin
    Open := TileWorldWalkable(tw, Floor(x), Floor(y));
  end;
begin
  TurnsPosFree :=
    Open(wx - BODY_RADIUS, wy - BODY_RADIUS) and
    Open(wx + BODY_RADIUS, wy - BODY_RADIUS) and
    Open(wx - BODY_RADIUS, wy + BODY_RADIUS) and
    Open(wx + BODY_RADIUS, wy + BODY_RADIUS);
end;

procedure MoveBody(var tw: TTileWorld; var px, py: Single; mvx, mvy: Single);
{ Slide a body by (mvx,mvy), each axis taken on its own so a wall stops one axis without
  stopping the other, and the tile the body ends in is never a wall. }
begin
  if (mvx <> 0) and TurnsPosFree(tw, px + mvx, py) then px := px + mvx;
  if (mvy <> 0) and TurnsPosFree(tw, px, py + mvy) then py := py + mvy;
end;

procedure MonsterUpdate(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; mi: LongInt; dt: Single);
var
  def: TMonsterDef;
  dxp, dyp, dist, spd, step: Single;
begin
  def := c.Monsters[es.List[mi].DefIdx];
  if es.List[mi].AtkCd > 0 then es.List[mi].AtkCd := es.List[mi].AtkCd - dt;

  if not es.List[mi].Awake then begin
    if HasLOS(tw, Floor(es.List[mi].Px), Floor(es.List[mi].Py),
              Floor(pl.Px), Floor(pl.Py), SIGHT) then
      es.List[mi].Awake := True
    else
      exit;
  end;

  dxp := pl.Px - es.List[mi].Px;
  dyp := pl.Py - es.List[mi].Py;
  dist := Sqrt(dxp * dxp + dyp * dyp);

  if dist <= MELEE_RANGE then begin
    if es.List[mi].AtkCd <= 0 then begin
      MonsterAttack(pl, def, es.List[mi].Bonus);
      es.List[mi].AtkCd := MON_SWING_CD;
    end;
    exit;
  end;

  { Close the gap, stopping a touch short of melee range so it does not jitter on top
    of the player. }
  spd := MON_MOVE_BASE * def.Speed;
  if spd < MON_MOVE_BASE then spd := MON_MOVE_BASE;
  step := spd * dt;
  if step > dist - MELEE_RANGE * 0.5 then step := dist - MELEE_RANGE * 0.5;
  if step > 0 then
    MoveBody(tw, es.List[mi].Px, es.List[mi].Py,
             dxp / dist * step, dyp / dist * step);
  es.List[mi].Cx := Floor(es.List[mi].Px);
  es.List[mi].Cy := Floor(es.List[mi].Py);
end;

procedure PickUp(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; pi: LongInt);
var
  def: TItemDef;
begin
  def := c.Items[es.List[pi].DefIdx];
  if not PlayerPickup(pl, es.List[pi].DefIdx) then begin
    Log(UIStr('msg_pack_full'));
    exit;
  end;
  es.List[pi].Alive := False;
  Dec(es.Props);
  EntitiesTakeProp(TileWorldDepth(tw),
    es.List[pi].OrigRx, es.List[pi].OrigRy, es.List[pi].OrigIdx);
  PlaySfx(SFX_PICKUP);
  Log(UIStrFmt('msg_pickup', [def.Name]));
end;

procedure TurnsPlayerSwing(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld);
var
  i, best: LongInt;
  dx, dy, d, bestD: Single;
begin
  if (not pl.Alive) or (pl.AtkCd > 0) then exit;
  pl.AtkCd := PLAYER_SWING_CD;
  best := -1;
  bestD := MELEE_RANGE;
  for i := 0 to es.Count - 1 do begin
    if (es.List[i].Kind <> enMonster) or (not es.List[i].Alive) then continue;
    dx := es.List[i].Px - pl.Px;
    dy := es.List[i].Py - pl.Py;
    d := Sqrt(dx * dx + dy * dy);
    if d <= bestD then begin best := i; bestD := d; end;
  end;
  if best < 0 then exit;
  pl.Facing := ArcTan2(es.List[best].Py - pl.Py, es.List[best].Px - pl.Px);
  PlaySfx(SFX_SWING);
  PlayerAttack(pl, es, c, tw, best);
end;

procedure OpenChest(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; pi: LongInt);
{ A locked chest opens only when a key is spent on it. With no key, it stays shut and
  says so once, until the player steps away and returns. }
var
  def: TItemDef;
begin
  def := c.Items[es.List[pi].DefIdx];
  if PlayerCountKind(pl, c, 'key') = 0 then begin
    if not es.List[pi].Notified then begin
      Log(UIStr('msg_chest_locked'));
      es.List[pi].Notified := True;
    end;
    exit;
  end;
  if pl.NCarry >= MAX_CARRY then begin
    if not es.List[pi].Notified then begin
      Log(UIStr('msg_chest_full'));
      es.List[pi].Notified := True;
    end;
    exit;
  end;
  PlayerConsumeKind(pl, c, 'key');
  PlayerPickup(pl, es.List[pi].DefIdx);
  es.List[pi].Alive := False;
  Dec(es.Props);
  EntitiesTakeProp(TileWorldDepth(tw),
    es.List[pi].OrigRx, es.List[pi].OrigRy, es.List[pi].OrigIdx);
  PlaySfx(SFX_PICKUP);
  Log(UIStrFmt('msg_chest_open', [def.Name]));
end;

procedure TurnsAutoPickup(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld);
var
  i: LongInt;
  dx, dy: Single;
begin
  if not pl.Alive then exit;
  for i := 0 to es.Count - 1 do begin
    if (es.List[i].Kind <> enProp) or (not es.List[i].Alive) then continue;
    dx := es.List[i].Px - pl.Px;
    dy := es.List[i].Py - pl.Py;
    if Sqrt(dx * dx + dy * dy) > PICKUP_RANGE then begin
      { Out of range again: a locked chest will speak once more on the next approach. }
      if es.List[i].Locked then es.List[i].Notified := False;
      continue;
    end;
    if es.List[i].Locked then begin OpenChest(pl, es, c, tw, i); continue; end;
    if pl.NCarry >= MAX_CARRY then begin Log(UIStr('msg_pack_full')); exit; end;
    PickUp(pl, es, c, tw, i);
  end;
end;

procedure TurnsUpdate(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; dt: Single);
var
  i: LongInt;
begin
  if pl.AtkCd > 0 then pl.AtkCd := pl.AtkCd - dt;
  if not pl.Alive then exit;
  for i := 0 to es.Count - 1 do begin
    if not pl.Alive then exit;
    if (es.List[i].Kind <> enMonster) or (not es.List[i].Alive) then continue;
    MonsterUpdate(pl, es, c, tw, i, dt);
  end;
end;

function TurnsAdjacentRole(const pl: TPlayer; const es: TEntitySet): LongInt;
const
  DX: array[0..3] of LongInt = (1, -1, 0, 0);
  DY: array[0..3] of LongInt = (0, 0, 1, -1);
var
  k, ti: LongInt;
begin
  for k := 0 to 3 do begin
    ti := EntityTownsfolkAt(es, pl.Cx + DX[k], pl.Cy + DY[k]);
    if ti >= 0 then exit(es.List[ti].Role);
  end;
  TurnsAdjacentRole := -1;
end;

function TurnsInteract(var pl: TPlayer; var es: TEntitySet;
  const c: TContent): Boolean;

  function AdjacentTownsperson: LongInt;
  const
    DX: array[0..3] of LongInt = (1, -1, 0, 0);
    DY: array[0..3] of LongInt = (0, 0, 1, -1);
  var
    k, ti: LongInt;
  begin
    for k := 0 to 3 do begin
      ti := EntityTownsfolkAt(es, pl.Cx + DX[k], pl.Cy + DY[k]);
      if ti >= 0 then exit(ti);
    end;
    AdjacentTownsperson := -1;
  end;

  procedure SellLoot;
  var
    i, total, sold, kept: LongInt;
  begin
    if pl.NCarry = 0 then begin
      Log(UIStr('msg_trader_light'));
      exit;
    end;
    { Sell the pack but keep the relic, which is never for sale. Surviving items are
      compacted back to the front of the pack. }
    total := 0; sold := 0; kept := 0;
    for i := 0 to pl.NCarry - 1 do
      if c.Items[pl.Carry[i]].Kind = 'relic' then begin
        pl.Carry[kept] := pl.Carry[i];
        Inc(kept);
      end else begin
        Inc(total, c.Items[pl.Carry[i]].Value);
        Inc(sold);
      end;
    pl.NCarry := kept;
    if sold = 0 then begin
      Log(UIStr('msg_trader_norelic'));
      exit;
    end;
    Log(UIStrFmt('msg_trader_pays', [total, sold]));
    Inc(pl.Gold, total);
  end;

  procedure Rest;
  begin
    if pl.Hp >= pl.MaxHp then
      Log(UIStr('msg_inn_hale'))
    else if pl.Gold >= INN_REST_COST then begin
      Dec(pl.Gold, INN_REST_COST);
      pl.Hp := pl.MaxHp;
      Log(UIStrFmt('msg_inn_rest', [INN_REST_COST]));
    end else
      Log(UIStr('msg_inn_nocoin'));
  end;

var
  ti, role: LongInt;
begin
  ti := AdjacentTownsperson;
  if ti < 0 then exit(False);
  role := es.List[ti].Role;
  Log(TownGreeting(role));
  case role of
    ROLE_TRADER:    SellLoot;
    ROLE_INNKEEPER: Rest;
  end;
  TurnsInteract := True;
end;

end.
