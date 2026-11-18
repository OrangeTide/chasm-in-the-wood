program t_quests;

{** Tests the quest loader and the runtime flag/quest logic. The real content/quests.txt
  parses into quests, derives, and logs; raising flags advances the objective, a derive
  fires when its sources are all set, completing a quest clears it from the objective,
  and the journal rebuilds from the flags. GL-free. }

{$mode objfpc}{$H+}

uses
  content, flags, quests;

var
  fails: LongInt;
  c: TContent;
  fs: TFlagSet;
  j: TJournal;
  qi: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function JournalHas(const j: TJournal; const s: String): Boolean;
var
  i: LongInt;
begin
  JournalHas := False;
  for i := 0 to High(j.Lines) do
    if j.Lines[i] = s then exit(True);
end;

begin
  fails := 0;

  Check(ContentLoad('content', c), 'ContentLoad reports success');
  writeln('  loaded ', Length(c.Quests), ' quests, ', Length(c.Derives),
          ' derives, ', Length(c.Logs), ' logs');

  { The relic quest parses: title, three stages, a done flag. }
  qi := QuestByIdx(c, 'Q_RELIC');
  Check(qi >= 0, 'Q_RELIC quest found');
  if qi >= 0 then begin
    Check(c.Quests[qi].Title = 'The Broken Relic', 'Q_RELIC title parsed');
    Check(Length(c.Quests[qi].Stages) = 3, 'Q_RELIC has three stages');
    Check(c.Quests[qi].Stages[0].Flag = 'QUEST_MAIN', 'Q_RELIC first stage flag');
    Check(c.Quests[qi].DoneFlag = 'QUEST_WON', 'Q_RELIC done flag parsed');
  end;
  Check(QuestByIdx(c, 'Q_CRYPT') >= 0, 'Q_CRYPT quest found');
  Check(Length(c.Derives) >= 1, 'a derive rule parsed');
  Check(Length(c.Logs) >= 2, 'log lines parsed');

  { No flags: nothing active, no objective. }
  FlagClearAll(fs);
  Check(QuestObjective(c, fs) = '', 'no objective before any flag');
  Check(not QuestActive(c, fs, QuestByIdx(c, 'Q_RELIC')), 'relic quest inactive at start');

  { Raising the main flag starts the relic quest at its first stage. }
  qi := QuestByIdx(c, 'Q_RELIC');
  QuestRaise(c, fs, 'QUEST_MAIN');
  Check(QuestActive(c, fs, qi), 'relic quest active after QUEST_MAIN');
  Check(QuestStageReached(c, fs, qi) = 0, 'reached stage 0');
  Check(QuestObjective(c, fs) = c.Quests[qi].Stages[0].Text, 'objective is stage 0 text');

  { Two of three shards do not yet derive the whole relic. }
  QuestRaise(c, fs, 'SHARD_CRYPT');
  QuestRaise(c, fs, 'SHARD_CAVE');
  Check(not FlagTest(fs, 'QUEST_RELIC'), 'relic not whole with two shards');
  Check(QuestStageReached(c, fs, qi) = 0, 'still on stage 0 with two shards');

  { The third shard fires the derive, which advances the quest to stage 1. }
  QuestRaise(c, fs, 'SHARD_INFER');
  Check(FlagTest(fs, 'QUEST_RELIC'), 'derive sets QUEST_RELIC on the third shard');
  Check(QuestStageReached(c, fs, qi) = 1, 'advanced to stage 1');
  Check(QuestObjective(c, fs) = c.Quests[qi].Stages[1].Text, 'objective is stage 1 text');

  { Completing the relic quest removes it from the HUD objective. }
  QuestRaise(c, fs, 'QUEST_DEPTHS');
  QuestRaise(c, fs, 'QUEST_WON');
  Check(QuestComplete(c, fs, qi), 'relic quest complete after QUEST_WON');
  Check(QuestObjective(c, fs) <> c.Quests[qi].Stages[2].Text,
        'completed quest no longer the objective');

  { The journal rebuilds from the flags: the log lines and the done lines are present. }
  QuestJournal(c, fs, j);
  Check(JournalHas(j, 'Took the cave shard from the grotto.'), 'cave-shard log in journal');
  Check(JournalHas(j, 'Tore the last shard from the demon lord.'), 'infer-shard log in journal');
  Check(JournalHas(j, 'You walked into the lost cities of the Sunless Depths.'),
        'relic done line in journal');

  { A fresh flag set settled after a load derives the same composite flags. }
  FlagClearAll(fs);
  FlagSet(fs, 'SHARD_CRYPT'); FlagSet(fs, 'SHARD_CAVE'); FlagSet(fs, 'SHARD_INFER');
  Check(not FlagTest(fs, 'QUEST_RELIC'), 'raw flags do not derive on their own');
  QuestSettle(c, fs);
  Check(FlagTest(fs, 'QUEST_RELIC'), 'QuestSettle derives QUEST_RELIC after a load');

  if fails = 0 then writeln('  ok') else writeln('  ', fails, ' FAILURES');
  if fails <> 0 then Halt(1);
end.
