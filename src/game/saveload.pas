unit saveload;
{ Save and restore the whole game state to a file. The world is deterministic from the  }
{ seed, so a save holds only what cannot be recomputed: the seed, where the player      }
{ stands (the town or a depth), the player's own state, and the two registries of       }
{ change (the monsters slain and the loot taken). Loading restores the registries and   }
{ the player, then the caller rebuilds the world from the seed and the saved location.   }

{$mode objfpc}{$H+}

interface

uses
  sysutils, classes, player, entities;

const
  SAVE_MAGIC   = 'CHASMSV3';   { eight bytes; the trailing digit is the format }
  SAVE_VERSION = 3;

type
  TSaveState = record
    Seed:   QWord;
    InTown: Boolean;
    Depth:  LongInt;
    Pl:     TPlayer;
  end;

{ Write the state and the change registries to path. False on any I/O failure. }
function SaveGame(const path: String; const st: TSaveState): Boolean;

{ Read a save written by SaveGame, restoring the registries as a side effect. False
  when the file is missing, not a save, or a version this build cannot read; the
  registries and st are left untouched in that case. }
function LoadGame(const path: String; out st: TSaveState): Boolean;

implementation

{ ---- stream helpers ---- }

procedure PutI(s: TStream; v: LongInt);
begin
  s.WriteBuffer(v, SizeOf(v));
end;

procedure PutQ(s: TStream; v: QWord);
begin
  s.WriteBuffer(v, SizeOf(v));
end;

function GetI(s: TStream): LongInt;
begin
  s.ReadBuffer(Result, SizeOf(Result));
end;

function GetQ(s: TStream): QWord;
begin
  s.ReadBuffer(Result, SizeOf(Result));
end;

procedure PutPlayer(s: TStream; const p: TPlayer);
var
  i: LongInt;
  sl: TEquipSlot;
begin
  PutI(s, p.Cx); PutI(s, p.Cy);
  PutI(s, p.Hp); PutI(s, p.MaxHp);
  PutI(s, p.Ac); PutI(s, p.Atk); PutI(s, p.DmgDie); PutI(s, p.DmgBonus);
  PutI(s, Ord(p.Alive));
  PutI(s, p.Gold);
  PutI(s, p.NCarry);
  for i := 0 to p.NCarry - 1 do PutI(s, p.Carry[i]);
  for sl := Low(TEquipSlot) to High(TEquipSlot) do PutI(s, p.Equip[sl]);
  { Identity and progression. }
  s.WriteBuffer(p.Name, SizeOf(p.Name));
  PutI(s, p.Species); PutI(s, p.Klass);
  PutI(s, p.Level); PutI(s, p.Xp);
  PutI(s, p.Str); PutI(s, p.Dex); PutI(s, p.Con);
  PutI(s, p.Int); PutI(s, p.Wis); PutI(s, p.Cha);
end;

procedure GetPlayer(s: TStream; out p: TPlayer);
var
  i: LongInt;
  sl: TEquipSlot;
begin
  p.Cx := GetI(s); p.Cy := GetI(s);
  p.Hp := GetI(s); p.MaxHp := GetI(s);
  p.Ac := GetI(s); p.Atk := GetI(s); p.DmgDie := GetI(s); p.DmgBonus := GetI(s);
  p.Alive := GetI(s) <> 0;
  p.Gold := GetI(s);
  p.NCarry := GetI(s);
  if p.NCarry < 0 then p.NCarry := 0;
  if p.NCarry > MAX_CARRY then p.NCarry := MAX_CARRY;
  for i := 0 to p.NCarry - 1 do p.Carry[i] := GetI(s);
  for sl := Low(TEquipSlot) to High(TEquipSlot) do p.Equip[sl] := GetI(s);
  s.ReadBuffer(p.Name, SizeOf(p.Name));
  p.Species := GetI(s); p.Klass := GetI(s);
  p.Level := GetI(s); p.Xp := GetI(s);
  p.Str := GetI(s); p.Dex := GetI(s); p.Con := GetI(s);
  p.Int := GetI(s); p.Wis := GetI(s); p.Cha := GetI(s);
end;

{ ---- public ---- }

function SaveGame(const path: String; const st: TSaveState): Boolean;
var
  s: TFileStream;
  i, n, d, rx, ry, idx: LongInt;
  magic: array[0 .. 7] of AnsiChar;
begin
  SaveGame := False;
  try
    s := TFileStream.Create(path, fmCreate);
  except
    exit;
  end;
  try
    Move(SAVE_MAGIC[1], magic[0], 8);
    s.WriteBuffer(magic, 8);
    PutI(s, SAVE_VERSION);
    PutQ(s, st.Seed);
    PutI(s, Ord(st.InTown));
    PutI(s, st.Depth);
    PutPlayer(s, st.Pl);
    { The slain registry, then the taken registry. }
    n := EntitiesSlainCount;
    PutI(s, n);
    for i := 0 to n - 1 do
      if EntitiesSlainKey(i, d, rx, ry, idx) then begin
        PutI(s, d); PutI(s, rx); PutI(s, ry); PutI(s, idx);
      end;
    n := EntitiesTakenCount;
    PutI(s, n);
    for i := 0 to n - 1 do
      if EntitiesTakenKey(i, d, rx, ry, idx) then begin
        PutI(s, d); PutI(s, rx); PutI(s, ry); PutI(s, idx);
      end;
  finally
    s.Free;
  end;
  SaveGame := True;
end;

function LoadGame(const path: String; out st: TSaveState): Boolean;
var
  s: TFileStream;
  i, n, d, rx, ry, idx: LongInt;
  magic: array[0 .. 7] of AnsiChar;
  want: array[0 .. 7] of AnsiChar;
begin
  LoadGame := False;
  if not FileExists(path) then exit;
  try
    s := TFileStream.Create(path, fmOpenRead or fmShareDenyWrite);
  except
    exit;
  end;
  try
    try
      s.ReadBuffer(magic, 8);
      Move(SAVE_MAGIC[1], want[0], 8);
      if not CompareMem(@magic[0], @want[0], 8) then exit;
      if GetI(s) <> SAVE_VERSION then exit;
      st.Seed := GetQ(s);
      st.InTown := GetI(s) <> 0;
      st.Depth := GetI(s);
      GetPlayer(s, st.Pl);
      { Restore the registries, replacing whatever is held now. }
      EntitiesClearSlain;
      n := GetI(s);
      for i := 0 to n - 1 do begin
        d := GetI(s); rx := GetI(s); ry := GetI(s); idx := GetI(s);
        EntitiesSlay(d, rx, ry, idx);
      end;
      EntitiesClearTaken;
      n := GetI(s);
      for i := 0 to n - 1 do begin
        d := GetI(s); rx := GetI(s); ry := GetI(s); idx := GetI(s);
        EntitiesTakeProp(d, rx, ry, idx);
      end;
    except
      exit;   { a truncated or malformed file: report failure }
    end;
  finally
    s.Free;
  end;
  LoadGame := True;
end;

end.
