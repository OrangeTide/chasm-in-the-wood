program t_dialog;

{** Tests the dialogue loader and runtime. The real content/dialogs.txt parses into
  dialogs, nodes, and responses; needflag hides a response until its flag is set; goto
  moves between nodes; a setflag response raises a quest flag and closes the talk; a shop
  response reports its id and leaves the talk standing. GL-free. }

{$mode objfpc}{$H+}

uses
  content, flags, dialogtext;

var
  fails: LongInt;
  c: TContent;
  ds: TDialogSet;
  fs: TFlagSet;
  cv: TConvo;
  oc: TDlgOutcome;
  labels: array[0..15] of String;
  picks:  array[0..15] of LongInt;
  n, i, elder: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

function HasLabel(cnt: LongInt; const s: String): Boolean;
var
  k: LongInt;
begin
  HasLabel := False;
  for k := 0 to cnt - 1 do
    if labels[k] = s then exit(True);
end;

function PickOf(cnt: LongInt; const s: String): LongInt;
var
  k: LongInt;
begin
  PickOf := -1;
  for k := 0 to cnt - 1 do
    if labels[k] = s then exit(picks[k]);
end;

begin
  fails := 0;

  Check(ContentLoad('content', c), 'ContentLoad reports success');
  Check(LoadDialogs('content/dialogs.txt', ds), 'LoadDialogs reports success');
  writeln('  loaded ', Length(ds.Dialogs), ' dialogs');
  Check(Length(ds.Dialogs) >= 8, 'at least eight dialogs parsed');

  { The barkeep opens with four responses, one of them a shop. }
  Check(ConvoStart(ds, 'BARKEEP', cv), 'BARKEEP conversation starts');
  Check(ConvoText(ds, cv) <> '', 'BARKEEP node 0 has narration');
  FlagClearAll(fs);
  n := ConvoResps(ds, cv, fs, labels, picks);
  Check(n = 4, 'BARKEEP node 0 offers four responses');
  Check(HasLabel(n, 'Show me your wares.'), 'BARKEEP has the shop response');

  { The shop response reports its id and leaves the talk open. }
  i := PickOf(n, 'Show me your wares.');
  ConvoChoose(ds, c, fs, cv, i, oc);
  Check(oc.Kind = daShop, 'shop response yields a shop outcome');
  Check(oc.Arg = 'GENERAL', 'shop outcome names the GENERAL shop');
  Check(cv.Dlg >= 0, 'shop response keeps the conversation open');

  { The elder gates one response behind QUEST_RELIC. }
  elder := DialogByIdx(ds, 'ELDER');
  Check(elder >= 0, 'ELDER dialog found');
  Check(ConvoStart(ds, 'ELDER', cv), 'ELDER conversation starts');
  FlagClearAll(fs);
  n := ConvoResps(ds, cv, fs, labels, picks);
  Check(not HasLabel(n, 'I bear the relic you sought.'),
        'relic response hidden without QUEST_RELIC');
  FlagSet(fs, 'QUEST_RELIC');
  n := ConvoResps(ds, cv, fs, labels, picks);
  Check(HasLabel(n, 'I bear the relic you sought.'),
        'relic response shown once QUEST_RELIC is set');

  { Walking the elder: ask what is wrong, then accept the charge raises QUEST_MAIN. }
  FlagClearAll(fs);
  ConvoStart(ds, 'ELDER', cv);
  n := ConvoResps(ds, cv, fs, labels, picks);
  i := PickOf(n, 'What is wrong?');
  ConvoChoose(ds, c, fs, cv, i, oc);
  Check(oc.Kind = daGoto, 'what-is-wrong is a goto');
  Check(cv.Node = 1, 'moved to node 1');
  n := ConvoResps(ds, cv, fs, labels, picks);
  i := PickOf(n, 'I accept the charge.');
  Check(i >= 0, 'accept response present at node 1');
  ConvoChoose(ds, c, fs, cv, i, oc);
  Check(oc.Kind = daSetflag, 'accept is a setflag');
  Check(FlagTest(fs, 'QUEST_MAIN'), 'accepting raised QUEST_MAIN');
  Check(cv.Dlg < 0, 'a setflag response closed the talk');

  { The shrine shard response raises SHARD_CRYPT. }
  FlagClearAll(fs);
  ConvoStart(ds, 'SHRINE', cv);
  n := ConvoResps(ds, cv, fs, labels, picks);
  i := PickOf(n, 'Take the crypt shard.');
  Check(i >= 0, 'shrine shard response present');
  ConvoChoose(ds, c, fs, cv, i, oc);
  Check(FlagTest(fs, 'SHARD_CRYPT'), 'taking the shard raised SHARD_CRYPT');

  { The demon lord offers a fight carrying the reward flag. }
  FlagClearAll(fs);
  ConvoStart(ds, 'DEMONLORD', cv);
  n := ConvoResps(ds, cv, fs, labels, picks);
  i := PickOf(n, 'Face the demon lord.');
  ConvoChoose(ds, c, fs, cv, i, oc);
  Check(oc.Kind = daFight, 'face-the-demon is a fight');
  Check(oc.Arg = 'DEMON', 'fight names the DEMON enemy');
  Check(oc.Arg2 = 'SHARD_INFER', 'fight carries the SHARD_INFER reward');
  Check(cv.Dlg < 0, 'a fight response closed the talk');

  if fails = 0 then writeln('  ok') else writeln('  ', fails, ' FAILURES');
  if fails <> 0 then Halt(1);
end.
