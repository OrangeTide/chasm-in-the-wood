unit quests;
{ Runtime quest state over the content quest tables (see content.pas) and a flag set    }
{ (see flags.pas). Dialogue and map events raise flags through QuestRaise, which also    }
{ sets any derived flags whose sources are all present. The quest log and the HUD read   }
{ the active quests, the current objective, and the journal back out of the flags, so    }
{ saving the flags alone restores the whole state.                                       }

{$mode objfpc}{$H+}

interface

uses
  content, flags;

type
  { The journal, rebuilt from the set flags: a line per 'log' flag that is set, plus a
    closing line per completed quest, in the order they appear in quests.txt. }
  TJournal = record
    Lines: array of String;
  end;

{ Raise a flag and settle: set it, then set every derived flag whose sources are now all
  present, repeating until nothing more follows. Returns True when the named flag was
  newly set. }
function QuestRaise(const c: TContent; var fs: TFlagSet; const name: String): Boolean;

{ Re-settle the derived flags without raising a new one, for use after a load restores
  the raw flag set. }
procedure QuestSettle(const c: TContent; var fs: TFlagSet);

{ A quest is active once any stage flag is set, and complete once its done flag is set. }
function QuestActive(const c: TContent; const fs: TFlagSet; qi: LongInt): Boolean;
function QuestComplete(const c: TContent; const fs: TFlagSet; qi: LongInt): Boolean;

{ The index of the furthest stage reached (the last stage whose flag is set), or -1 when
  the quest has not started. }
function QuestStageReached(const c: TContent; const fs: TFlagSet; qi: LongInt): LongInt;

{ The one objective line for the HUD: the current stage of the first active, incomplete
  quest, or '' when none is in play. }
function QuestObjective(const c: TContent; const fs: TFlagSet): String;

{ Build the journal from the set flags. }
procedure QuestJournal(const c: TContent; const fs: TFlagSet; out j: TJournal);

implementation

function AllSourcesSet(const fs: TFlagSet; const d: TDeriveRule): Boolean;
var
  i: LongInt;
begin
  if Length(d.Sources) = 0 then exit(False);
  for i := 0 to High(d.Sources) do
    if not FlagTest(fs, d.Sources[i]) then exit(False);
  AllSourcesSet := True;
end;

procedure Cascade(const c: TContent; var fs: TFlagSet);
var
  changed: Boolean;
  i: LongInt;
begin
  repeat
    changed := False;
    for i := 0 to High(c.Derives) do
      if (c.Derives[i].Target <> '') and not FlagTest(fs, c.Derives[i].Target)
         and AllSourcesSet(fs, c.Derives[i]) then
        if FlagSet(fs, c.Derives[i].Target) then changed := True;
  until not changed;
end;

function QuestRaise(const c: TContent; var fs: TFlagSet; const name: String): Boolean;
begin
  QuestRaise := FlagSet(fs, name);
  Cascade(c, fs);
end;

procedure QuestSettle(const c: TContent; var fs: TFlagSet);
begin
  Cascade(c, fs);
end;

function QuestStageReached(const c: TContent; const fs: TFlagSet; qi: LongInt): LongInt;
var
  i: LongInt;
begin
  QuestStageReached := -1;
  if (qi < 0) or (qi > High(c.Quests)) then exit;
  for i := 0 to High(c.Quests[qi].Stages) do
    if FlagTest(fs, c.Quests[qi].Stages[i].Flag) then QuestStageReached := i;
end;

function QuestActive(const c: TContent; const fs: TFlagSet; qi: LongInt): Boolean;
begin
  QuestActive := QuestStageReached(c, fs, qi) >= 0;
end;

function QuestComplete(const c: TContent; const fs: TFlagSet; qi: LongInt): Boolean;
begin
  QuestComplete := False;
  if (qi < 0) or (qi > High(c.Quests)) then exit;
  QuestComplete := (c.Quests[qi].DoneFlag <> '') and FlagTest(fs, c.Quests[qi].DoneFlag);
end;

function QuestObjective(const c: TContent; const fs: TFlagSet): String;
var
  i, st: LongInt;
begin
  QuestObjective := '';
  for i := 0 to High(c.Quests) do
    if QuestActive(c, fs, i) and not QuestComplete(c, fs, i) then begin
      st := QuestStageReached(c, fs, i);
      if st >= 0 then exit(c.Quests[i].Stages[st].Text);
    end;
end;

procedure QuestJournal(const c: TContent; const fs: TFlagSet; out j: TJournal);

  procedure Add(const s: String);
  var
    k: LongInt;
  begin
    if s = '' then exit;
    k := Length(j.Lines);
    SetLength(j.Lines, k + 1);
    j.Lines[k] := s;
  end;

var
  i, qi: LongInt;
begin
  SetLength(j.Lines, 0);
  { 'log' events that have fired. }
  for i := 0 to High(c.Logs) do
    if FlagTest(fs, c.Logs[i].Flag) then Add(c.Logs[i].Text);
  { closing lines of completed quests. }
  for qi := 0 to High(c.Quests) do
    if QuestComplete(c, fs, qi) then Add(c.Quests[qi].DoneText);
end;

end.
