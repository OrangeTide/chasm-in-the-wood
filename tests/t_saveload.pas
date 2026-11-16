program t_saveload;

{** Tests saving and loading. A round trip through a file reproduces the seed, the
  location, the player's stats and pack, and the registries of slain monsters and taken
  loot. A missing or malformed file is refused without disturbing the registries. }

{$mode objfpc}{$H+}

uses
  sysutils, classes, player, entities, saveload;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

const
  TMP = 'build/tests/t_saveload.tmp';

var
  st, got: TSaveState;
  junk: String;
begin
  fails := 0;

  { A loaded game with some history: two kills and one pickup. }
  EntitiesClearSlain;
  EntitiesClearTaken;
  EntitiesSlay(0, 1, 2, 3);
  EntitiesSlay(2, -1, 4, 0);
  EntitiesTakeProp(1, 5, 6, 7);

  st.Seed := QWord($0123456789ABCDEF);
  st.InTown := False;
  st.Depth := 3;
  PlayerInit(st.Pl, 40, -12);
  st.Pl.Hp := 7; st.Pl.MaxHp := 20;
  st.Pl.Gold := 42;
  st.Pl.NCarry := 3;
  st.Pl.Carry[0] := 5; st.Pl.Carry[1] := 9; st.Pl.Carry[2] := 0;

  Check(SaveGame(TMP, st), 'save writes the file');

  { Wipe the registries and load; the file must restore everything. }
  EntitiesClearSlain;
  EntitiesClearTaken;
  Check(LoadGame(TMP, got), 'load reads the file');

  Check(got.Seed = st.Seed, 'seed round-trips');
  Check(got.InTown = st.InTown, 'town flag round-trips');
  Check(got.Depth = st.Depth, 'depth round-trips');
  Check((got.Pl.Cx = 40) and (got.Pl.Cy = -12), 'player position round-trips');
  Check((got.Pl.Hp = 7) and (got.Pl.MaxHp = 20), 'player health round-trips');
  Check(got.Pl.Gold = 42, 'gold round-trips');
  Check(got.Pl.NCarry = 3, 'pack size round-trips');
  Check((got.Pl.Carry[0] = 5) and (got.Pl.Carry[1] = 9) and (got.Pl.Carry[2] = 0),
        'pack contents round-trip');

  { The registries were restored by the load. }
  Check(EntitiesSlainCount = 2, 'slain count restored');
  Check(EntitiesTakenCount = 1, 'taken count restored');
  Check(EntitiesIsSlain(0, 1, 2, 3), 'first kill restored');
  Check(EntitiesIsSlain(2, -1, 4, 0), 'second kill restored');
  Check(EntitiesIsTaken(1, 5, 6, 7), 'taken loot restored');
  Check(not EntitiesIsSlain(9, 9, 9, 9), 'unrelated key not slain');

  { A missing file is refused and leaves the registries alone. }
  DeleteFile(TMP);
  Check(not LoadGame(TMP, got), 'missing save is refused');
  Check(EntitiesSlainCount = 2, 'a failed load does not clear the registries');

  { A truncated file is refused too. }
  EntitiesClearSlain; EntitiesClearTaken;
  EntitiesSlay(5, 5, 5, 5);
  junk := 'CHASM';   { too short to be a valid header }
  with TFileStream.Create(TMP, fmCreate) do begin
    WriteBuffer(junk[1], Length(junk));
    Free;
  end;
  Check(not LoadGame(TMP, got), 'a malformed save is refused');
  Check(EntitiesSlainCount = 1, 'a refused load leaves the registry intact');
  DeleteFile(TMP);

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
