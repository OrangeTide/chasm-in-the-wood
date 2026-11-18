program t_saveload;

{** Tests saving and loading. A round trip through a file reproduces the seed, the
  location, the player's stats and pack, the quest flags, and the registries of slain
  monsters, taken loot, and opened doors. A missing or malformed file is refused without
  disturbing the registries. }

{$mode objfpc}{$H+}

uses
  sysutils, classes, player, entities, flags, tileworld, saveload;

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
  TileWorldClearOpened;
  EntitiesSlay(0, 1, 2, 3);
  EntitiesSlay(2, -1, 4, 0);
  EntitiesTakeProp(1, 5, 6, 7);
  TileWorldMarkOpened(1, 10, 20);
  TileWorldMarkOpened(3, -5, 7);

  st.Seed := QWord($0123456789ABCDEF);
  st.InTown := False;
  st.Depth := 3;
  st.DeepReached := 5;
  PlayerInit(st.Pl, 40, -12);
  st.Pl.Hp := 7; st.Pl.MaxHp := 20;
  st.Pl.Gold := 42;
  st.Pl.Background := 4;
  st.Pl.NCarry := 3;
  st.Pl.Carry[0] := 5; st.Pl.Carry[1] := 9; st.Pl.Carry[2] := 0;
  FlagClearAll(st.Flags);
  FlagSet(st.Flags, 'QUEST_MAIN');
  FlagSet(st.Flags, 'SHARD_CRYPT');
  FlagSet(st.Flags, 'DEMON_WOKE');

  Check(SaveGame(TMP, st), 'save writes the file');

  { Wipe the registries and load; the file must restore everything. }
  EntitiesClearSlain;
  EntitiesClearTaken;
  TileWorldClearOpened;
  Check(LoadGame(TMP, got), 'load reads the file');

  Check(got.Seed = st.Seed, 'seed round-trips');
  Check(got.InTown = st.InTown, 'town flag round-trips');
  Check(got.Depth = st.Depth, 'depth round-trips');
  Check(got.DeepReached = st.DeepReached, 'deepest reach round-trips');
  Check((got.Pl.Cx = 40) and (got.Pl.Cy = -12), 'player position round-trips');
  Check((got.Pl.Hp = 7) and (got.Pl.MaxHp = 20), 'player health round-trips');
  Check(got.Pl.Gold = 42, 'gold round-trips');
  Check(got.Pl.Background = 4, 'background round-trips');
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

  { The flags round-trip, and only the saved ones are set. }
  Check(FlagCount(got.Flags) = 3, 'flag count round-trips');
  Check(FlagTest(got.Flags, 'QUEST_MAIN'), 'QUEST_MAIN flag restored');
  Check(FlagTest(got.Flags, 'SHARD_CRYPT'), 'SHARD_CRYPT flag restored');
  Check(FlagTest(got.Flags, 'DEMON_WOKE'), 'DEMON_WOKE flag restored');
  Check(not FlagTest(got.Flags, 'QUEST_WON'), 'an unset flag stays unset');

  { The opened-door registry was restored by the load. }
  Check(TileWorldOpenedCount = 2, 'opened-door count restored');
  Check(TileWorldDoorOpened(1, 10, 20), 'first opened door restored');
  Check(TileWorldDoorOpened(3, -5, 7), 'second opened door restored');
  Check(not TileWorldDoorOpened(0, 0, 0), 'unrelated door not opened');

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
