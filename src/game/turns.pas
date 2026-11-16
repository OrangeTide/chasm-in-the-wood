unit turns;
{ The turn loop and melee combat. A player action (a move, or an attack into an       }
{ occupied tile) spends one turn; bumping a wall spends none. After the player acts,   }
{ the clock advances the monsters: each live monster gains energy by its speed and     }
{ acts while it has enough, so a faster monster acts more often. A sleeping monster    }
{ idles until it sights the player, then chases and strikes when adjacent. Death is     }
{ resolved here: a slain monster is recorded so its room stays empty, and a slain      }
{ player is marked for the caller to respawn. Combat is reported through a small log.   }

{$mode objfpc}{$H+}

interface

uses
  sysutils, tilemap, tileworld, content, player, entities, rng;

const
  PLAYER_SPEED = 4;    { the player's speed, and so the energy an action costs }
  SIGHT        = 10;   { tiles within which a monster can sight the player }

{ Seed the combat RNG. Combat is not required to reproduce, but a fixed seed makes
  tests and screenshots repeatable. }
procedure TurnsSeed(seed: QWord);

{ The player's response to a movement key: attack a monster on the target tile, or
  step onto it when open. Returns True if a turn was spent. }
function TurnsPlayerAct(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; dx, dy: LongInt): Boolean;

{ Advance the monsters by one player turn's worth of time. }
procedure TurnsRunMonsters(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld);

{ Combat log, oldest kept entry first. }
function TurnsLogCount: LongInt;
function TurnsLogLine(i: LongInt): String;
procedure TurnsLogClear;

implementation

const
  LOG_MAX = 8;

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
  dmg: LongInt;
begin
  def := c.Monsters[es.List[mi].DefIdx];
  es.List[mi].Awake := True;
  if AttackHits(pl.Atk, def.AC) then begin
    dmg := Die(pl.DmgDie);
    Dec(es.List[mi].Hp, dmg);
    Log('You hit ' + def.Name + ' for ' + IntToStr(dmg) + '.');
    if es.List[mi].Hp <= 0 then KillMonster(es, mi, def, TileWorldDepth(tw));
  end else
    Log('You miss ' + def.Name + '.');
end;

procedure MonsterAttack(var pl: TPlayer; const def: TMonsterDef);
var
  dmg: LongInt;
begin
  if AttackHits(def.Atk, pl.Ac) then begin
    dmg := Die(def.Dmg);
    Dec(pl.Hp, dmg);
    Log(def.Name + ' hits you for ' + IntToStr(dmg) + '.');
    if pl.Hp <= 0 then begin
      pl.Hp := 0;
      pl.Alive := False;
      Log('You die.');
    end;
  end else
    Log(def.Name + ' misses you.');
end;

function TryStep(var pl: TPlayer; var es: TEntitySet; var tw: TTileWorld;
  mi, dx, dy: LongInt): Boolean;
{ Move monster mi one tile if the target is open floor, not the player, and not held
  by another monster. }
var
  nx, ny: LongInt;
begin
  nx := es.List[mi].Cx + dx;
  ny := es.List[mi].Cy + dy;
  if (nx = pl.Cx) and (ny = pl.Cy) then exit(False);
  if not TileWorldWalkable(tw, nx, ny) then exit(False);
  if EntityBlocked(es, nx, ny) then exit(False);
  es.List[mi].Cx := nx;
  es.List[mi].Cy := ny;
  TryStep := True;
end;

procedure MonsterTurn(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; mi: LongInt);
var
  def: TMonsterDef;
  dxp, dyp, sx, sy: LongInt;
begin
  def := c.Monsters[es.List[mi].DefIdx];
  if not es.List[mi].Awake then begin
    if HasLOS(tw, es.List[mi].Cx, es.List[mi].Cy, pl.Cx, pl.Cy, SIGHT) then
      es.List[mi].Awake := True
    else
      exit;
  end;
  dxp := pl.Cx - es.List[mi].Cx;
  dyp := pl.Cy - es.List[mi].Cy;
  if (Abs(dxp) + Abs(dyp)) = 1 then begin
    MonsterAttack(pl, def);
    exit;
  end;
  sx := SignOf(dxp);
  sy := SignOf(dyp);
  if Abs(dxp) >= Abs(dyp) then begin
    if TryStep(pl, es, tw, mi, sx, 0) then exit;
    if (sy <> 0) and TryStep(pl, es, tw, mi, 0, sy) then exit;
  end else begin
    if TryStep(pl, es, tw, mi, 0, sy) then exit;
    if (sx <> 0) and TryStep(pl, es, tw, mi, sx, 0) then exit;
  end;
end;

function TurnsPlayerAct(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld; dx, dy: LongInt): Boolean;
var
  tx, ty, mi: LongInt;
begin
  if not pl.Alive then exit(False);
  tx := pl.Cx + dx;
  ty := pl.Cy + dy;
  mi := EntityMonsterAt(es, tx, ty);
  if mi >= 0 then begin
    PlayerAttack(pl, es, c, tw, mi);
    exit(True);
  end;
  if TileWorldWalkable(tw, tx, ty) then begin
    pl.Cx := tx;
    pl.Cy := ty;
    exit(True);
  end;
  TurnsPlayerAct := False;
end;

procedure TurnsRunMonsters(var pl: TPlayer; var es: TEntitySet; const c: TContent;
  var tw: TTileWorld);
{ Each live monster gains energy by its own speed and acts while it holds at least the
  player's speed, so a faster monster takes more actions per player turn. }
var
  i, spd: LongInt;
begin
  for i := 0 to es.Count - 1 do begin
    if not pl.Alive then exit;
    if (es.List[i].Kind <> enMonster) or (not es.List[i].Alive) then continue;
    spd := c.Monsters[es.List[i].DefIdx].Speed;
    if spd < 1 then spd := 1;
    Inc(es.List[i].Energy, spd);
    while (es.List[i].Energy >= PLAYER_SPEED) and es.List[i].Alive and pl.Alive do begin
      Dec(es.List[i].Energy, PLAYER_SPEED);
      MonsterTurn(pl, es, c, tw, i);
    end;
  end;
end;

end.
