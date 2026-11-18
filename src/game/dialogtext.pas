unit dialogtext;
{ Conversations: the dialog tables (dialogs.txt) and the runtime that walks them over a  }
{ flag set. A dialog is a list of nodes; a node shows a line of narration and a set of    }
{ player responses. Choosing a response acts: move to another node, raise a flag, open a  }
{ shop, or hand a world action (recruit, revive, identify, fight) back to the host. A     }
{ response guarded by needflag is offered only once that flag is set. Raising a flag goes }
{ through the quest system, so a dialogue drives quests and the journal (see quests.pas). }

{$mode objfpc}{$H+}

interface

uses
  content, flags;

type
  { What a response does when chosen. }
  TDlgActKind = (daGoto, daSetflag, daEnd, daShop, daRecruit, daRevive,
                 daIdentify, daFight);

  { One player response. Need is a flag that must be set for it to be offered ('' means
    always). For daGoto, Target is the node to move to; for daSetflag, Arg is the flag;
    for daShop, Arg is the shop id; for daFight, Arg is the enemy id and Arg2 the flag
    granted on the win. }
  TDlgResp = record
    Text:   String;
    Kind:   TDlgActKind;
    Target: LongInt;
    Arg:    String;
    Arg2:   String;
    Need:   String;
  end;

  { A node: a line of narration and the responses offered under it. }
  TDlgNode = record
    Text:  String;
    Resps: array of TDlgResp;
  end;

  TDialogDef = record
    Id:    String;
    Nodes: array of TDlgNode;
  end;

  TDialogSet = record
    Dialogs: array of TDialogDef;
  end;

  { A running conversation: which dialog, and which node within it. Dlg = -1 means no
    conversation is in play (the last response closed it). }
  TConvo = record
    Dlg:  LongInt;
    Node: LongInt;
  end;

  { The side effect a chosen response hands back to the host. Goto/Setflag/End are settled
    inside ConvoChoose; the rest name an action the host must carry out. }
  TDlgOutcome = record
    Kind: TDlgActKind;
    Arg:  String;    { shop id, or fight enemy id }
    Arg2: String;    { fight reward flag }
  end;

{ Load dialogs.txt. Returns False only when the file is missing or unreadable. }
function LoadDialogs(const path: String; out ds: TDialogSet): Boolean;

{ Index of the dialog with this id, or -1. }
function DialogByIdx(const ds: TDialogSet; const id: String): LongInt;

{ Begin a conversation at a dialog's first node. Returns False when the id is unknown. }
function ConvoStart(const ds: TDialogSet; const id: String; out cv: TConvo): Boolean;

{ The current node's narration text, or '' when the conversation is closed. }
function ConvoText(const ds: TDialogSet; const cv: TConvo): String;

{ The responses offered at the current node, after dropping any whose needflag is unset.
  labels[k] is the response text and picks[k] its index within the node; returns the
  count. Both arrays must hold at least that many entries. }
function ConvoResps(const ds: TDialogSet; const cv: TConvo; const fs: TFlagSet;
  out labels: array of String; out picks: array of LongInt): LongInt;

{ Choose the response at node index ri (a value from picks). Goto moves the node, setflag
  raises the flag (and closes), end closes; the outcome names what the host must do and,
  for a closing response, leaves cv.Dlg at -1. }
procedure ConvoChoose(const ds: TDialogSet; const c: TContent; var fs: TFlagSet;
  var cv: TConvo; ri: LongInt; out oc: TDlgOutcome);

implementation

uses
  sysutils, quests;

function LoadDialogs(const path: String; out ds: TDialogSet): Boolean;
var
  f: TextFile;
  line: String;
  tok: array[0..63] of String;
  n, di, ni, ri, p, a0, a1, i: LongInt;
begin
  SetLength(ds.Dialogs, 0);
  LoadDialogs := False;
  if not FileExists(path) then exit;
  AssignFile(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then exit;
  di := -1; ni := -1;
  try
    while not Eof(f) do begin
      ReadLn(f, line);
      if Skip(line) then continue;
      Tokenize(line, tok, n);
      if n < 1 then continue;
      if (tok[0] = 'dialog') and (n >= 2) then begin
        di := Length(ds.Dialogs);
        SetLength(ds.Dialogs, di + 1);
        ds.Dialogs[di].Id := tok[1];
        SetLength(ds.Dialogs[di].Nodes, 0);
        ni := -1;
      end else if (tok[0] = 'node') and (di >= 0) then begin
        ni := Length(ds.Dialogs[di].Nodes);
        SetLength(ds.Dialogs[di].Nodes, ni + 1);
        ds.Dialogs[di].Nodes[ni].Text := '';
        SetLength(ds.Dialogs[di].Nodes[ni].Resps, 0);
      end else if (tok[0] = 'text') and (n >= 2) and (ni >= 0) then begin
        ds.Dialogs[di].Nodes[ni].Text := tok[1];
      end else if (tok[0] = 'resp') and (n >= 3) and (ni >= 0) then begin
        ri := Length(ds.Dialogs[di].Nodes[ni].Resps);
        SetLength(ds.Dialogs[di].Nodes[ni].Resps, ri + 1);
        with ds.Dialogs[di].Nodes[ni].Resps[ri] do begin
          Text := tok[1];
          Kind := daEnd; Target := 0; Arg := ''; Arg2 := ''; Need := '';
          { Pull an optional 'needflag FLAG' out of the token run, wherever it sits; the
            action tokens are those before it. }
          a0 := 2; a1 := n - 1;
          for i := 2 to n - 1 do
            if (tok[i] = 'needflag') and (i + 1 <= n - 1) then begin
              Need := tok[i + 1];
              if i - 1 < a1 then a1 := i - 1;
            end;
          p := a0;                               { p is the action verb }
          if tok[p] = 'goto' then begin
            Kind := daGoto;
            if p + 1 <= a1 then Target := StrToIntDef(tok[p + 1], 0);
          end else if tok[p] = 'setflag' then begin
            Kind := daSetflag;
            if p + 1 <= a1 then Arg := tok[p + 1];
          end else if tok[p] = 'shop' then begin
            Kind := daShop;
            if p + 1 <= a1 then Arg := tok[p + 1];
          end else if tok[p] = 'fight' then begin
            Kind := daFight;
            if p + 1 <= a1 then Arg := tok[p + 1];
            if p + 2 <= a1 then Arg2 := tok[p + 2];
          end else if tok[p] = 'recruit' then
            Kind := daRecruit
          else if tok[p] = 'revive' then
            Kind := daRevive
          else if tok[p] = 'identify' then
            Kind := daIdentify
          else
            Kind := daEnd;                        { 'end' and anything unknown }
        end;
      end;
    end;
  finally
    CloseFile(f);
  end;
  LoadDialogs := True;
end;

function DialogByIdx(const ds: TDialogSet; const id: String): LongInt;
var
  i: LongInt;
begin
  for i := 0 to High(ds.Dialogs) do
    if ds.Dialogs[i].Id = id then exit(i);
  DialogByIdx := -1;
end;

function ConvoStart(const ds: TDialogSet; const id: String; out cv: TConvo): Boolean;
begin
  cv.Dlg := DialogByIdx(ds, id);
  cv.Node := 0;
  ConvoStart := cv.Dlg >= 0;
end;

function ConvoText(const ds: TDialogSet; const cv: TConvo): String;
begin
  ConvoText := '';
  if (cv.Dlg < 0) or (cv.Dlg > High(ds.Dialogs)) then exit;
  if (cv.Node < 0) or (cv.Node > High(ds.Dialogs[cv.Dlg].Nodes)) then exit;
  ConvoText := ds.Dialogs[cv.Dlg].Nodes[cv.Node].Text;
end;

function ConvoResps(const ds: TDialogSet; const cv: TConvo; const fs: TFlagSet;
  out labels: array of String; out picks: array of LongInt): LongInt;
var
  i, k: LongInt;
begin
  k := 0;
  ConvoResps := 0;
  if (cv.Dlg < 0) or (cv.Dlg > High(ds.Dialogs)) then exit;
  if (cv.Node < 0) or (cv.Node > High(ds.Dialogs[cv.Dlg].Nodes)) then exit;
  with ds.Dialogs[cv.Dlg].Nodes[cv.Node] do
    for i := 0 to High(Resps) do begin
      if (Resps[i].Need <> '') and not FlagTest(fs, Resps[i].Need) then continue;
      if k > High(labels) then break;
      labels[k] := Resps[i].Text;
      picks[k] := i;
      Inc(k);
    end;
  ConvoResps := k;
end;

procedure ConvoChoose(const ds: TDialogSet; const c: TContent; var fs: TFlagSet;
  var cv: TConvo; ri: LongInt; out oc: TDlgOutcome);
var
  r: TDlgResp;
begin
  oc.Kind := daEnd; oc.Arg := ''; oc.Arg2 := '';
  if (cv.Dlg < 0) or (cv.Dlg > High(ds.Dialogs)) then exit;
  if (cv.Node < 0) or (cv.Node > High(ds.Dialogs[cv.Dlg].Nodes)) then exit;
  if (ri < 0) or (ri > High(ds.Dialogs[cv.Dlg].Nodes[cv.Node].Resps)) then exit;
  r := ds.Dialogs[cv.Dlg].Nodes[cv.Node].Resps[ri];
  oc.Kind := r.Kind; oc.Arg := r.Arg; oc.Arg2 := r.Arg2;
  case r.Kind of
    daGoto:
      if (r.Target >= 0) and (r.Target <= High(ds.Dialogs[cv.Dlg].Nodes)) then
        cv.Node := r.Target;
    daSetflag: begin
        QuestRaise(c, fs, r.Arg);
        cv.Dlg := -1;                 { a flag-raising response closes the talk }
      end;
    daEnd, daFight:
      cv.Dlg := -1;                   { these close; the host may start combat }
    { daShop, daRecruit, daRevive, daIdentify leave the conversation standing so the
      player can pick again once the host has acted. }
  end;
end;

end.
