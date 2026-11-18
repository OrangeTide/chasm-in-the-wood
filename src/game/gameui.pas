unit gameui;
{ The game's interface layer: a desktop of floating windows over the diorama.    }
{ It wraps the gui toolkit behind a plain procedural API so the main program can  }
{ drive it with integers and strings, and never sees the toolkit's own types.    }

{$mode objfpc}{$H+}

interface

type
  { One item as the panels need it: the content index as a payload tag, the drop
    category, an ARGB tile colour, a glyph, and a name. A Tag of -1 means an empty
    worn slot. The game layer fills these; the interface never sees content types. }
  TUIItem = record
    Tag:   LongInt;
    Cat:   LongInt;
    Color: LongInt;
    Glyph: Char;
    Name:  String;
    Price: LongInt;    { for the trade window; 0 elsewhere }
  end;

  { Called when the player confirms a trade: the pack slots handed over and the content
    item indices taken from the shop. The game settles it and refreshes the window. }
  TTradeProc = procedure(const giveSlots: array of LongInt;
                         const takeItems: array of LongInt);

  { Called when the player rearranges the pack or the worn gear by dragging. The pack
    is the filled bag slots in order; the three worn tags are the content indices worn,
    or -1 when a slot is bare. }
  TInvChangeProc = procedure(const packTags: array of LongInt;
                             weaponTag, armorTag, shieldTag: LongInt);

{ Build the desktop and the status window for a viewW x viewH framebuffer. }
procedure GameUIInit(viewW, viewH: LongInt);

{ Replace the status panel's text with these lines. }
procedure GameUISetStatus(const lines: array of String);

{ Replace the transparent message-log panel's text with these lines. }
procedure GameUISetLog(const lines: array of String);

{ Point the HUD compass at the objective: angle is the heading in radians, 0 straight
  ahead and growing clockwise, with the label shown beneath the arrow. show = False
  hides it (no current objective). }
procedure GameUISetCompass(angle: Single; const caption: String; show: Boolean);

{ The drop category (a CAT_* bit) an item of this kind takes. }
function GameUIItemCat(const kind: String): LongInt;

{ Replace the pack contents shown in the inventory window. }
procedure GameUISetInventory(const items: array of TUIItem);

{ Replace the three worn slots on the equipment doll. A Tag of -1 empties a slot. }
procedure GameUISetWorn(const weapon, armor, shield: TUIItem);

{ Replace the live stat lines on the character sheet. }
procedure GameUISetCharStats(const lines: array of String);

{ Register the callback run after the player drags an item in the panels. }
procedure GameUISetInvChange(cb: TInvChangeProc);

type
  { Called on Begin in the creation window, with the chosen content indices and name. }
  TGameCreateProc = procedure(speciesIdx, classIdx, bgIdx: LongInt; const name: String);

{ Build the character-creation window (hidden) from the species names (in content order),
  the offered class names and their content indices (in step), the background names (in
  content order), and the name pool. defSp, defCl, and defBg are the initial species,
  class, and background content indices. }
procedure GameUIInitCreate(const spNames, clNames: array of String;
  const clIdx: array of LongInt; const bgNames, names: array of String;
  defSp, defCl, defBg: LongInt);

{ Show the creation window. }
procedure GameUIShowCreate;

{ Register the callback run when the player presses Begin. }
procedure GameUISetCreateDone(cb: TGameCreateProc);

type
  { Called when the player clicks a front-end menu button, with that button's action
    tag (a value the game chose when it built the menu). }
  TGameMenuProc = procedure(action: LongInt);

{ Show the centered front-end menu (title, victory, or death) with a heading, body
  lines, and buttons; labels and actions run in step. It holds until a button is
  clicked. }
procedure GameUIShowMenu(const heading: String; const lines, labels: array of String;
  const actions: array of LongInt);

{ Hide the front-end menu. }
procedure GameUIHideMenu;

{ Whether the front-end menu is showing. }
function GameUIMenuShown: Boolean;

{ Register the callback run when a menu button is clicked. }
procedure GameUISetMenuPick(cb: TGameMenuProc);

{ Open the trade window for a shop. title is the trader's name; stock is the shop's
  items (Tag the content index, Price the buy price) and pack the player's items (Tag
  the pack slot, Price the sell price); gold is the purse. Call again to refresh. }
procedure GameUIOpenTrade(const title: String;
  const stock, pack: array of TUIItem; gold: LongInt);

{ Close the trade window. }
procedure GameUICloseTrade;

{ Whether the trade window is open. }
function GameUITradeOpen: Boolean;

{ Register the callback run when the player confirms a trade. }
procedure GameUISetTradeDone(cb: TTradeProc);

{ Replace the character sheet's identity header. }
procedure GameUISetCharIdentity(const name, klass, species: String);

{ Replace the quest-log lines (active quests, objectives, journal). }
procedure GameUISetQuests(const lines: array of String);

{ Toggle a floating panel: 0 inventory (with the equipment doll), 1 character
  sheet, 2 options. The same call shows a hidden panel and hides a shown one. }
procedure GameUITogglePanel(id: LongInt);

{ Feed a mouse event: kind 0 down, 1 up, 2 move, 3 wheel; button 0 left, 1 middle,
  2 right; wheel the signed scroll delta. }
procedure GameUIMouse(kind, x, y, button, wheel: LongInt);

{ Draw the desktop as an overlay. Call after the 3D scene, before the buffer swap. }
procedure GameUIRender;

procedure GameUIFree;

implementation

uses
  sysutils, gui, guitheme, guigl, panels, uitext;

type
  { A panel that draws a list of text lines, the live game status. }
  THudPanel = class(TWidget)
  private
    FLines: array of String;
  public
    procedure SetLines(const lines: array of String);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { A transparent overlay that tails the message log: bright text with a drop shadow,
    no window chrome and no background, and it never intercepts the mouse. }
  TLogPanel = class(TWidget)
  private
    FLines: array of String;
  public
    procedure SetLines(const lines: array of String);
    function  HitTest(const p: TPoint): TWidget; override;
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { A transparent overlay drawing an arrow toward the objective and its name. The arrow
    heading is set in screen space (0 up, clockwise). Never intercepts the mouse. }
  TCompassPanel = class(TWidget)
  private
    FAngle: Single;
    FLabel: String;
    FShow:  Boolean;
  public
    procedure SetTarget(angle: Single; const caption: String; show: Boolean);
    function  HitTest(const p: TPoint): TWidget; override;
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { Owns the toggle panels and routes the HUD button clicks to them. A plain
    object, not a widget: its methods are the buttons' OnClick handlers. }
  TUIController = class
  public
    Inv:  TInventoryWindow;
    Equ:  TEquipmentWindow;
    Chr:  TCharacterSheet;
    Opts: TOptionsWindow;
    Crt:  TCharCreateWindow;
    Trd:  TTradeWindow;
    Mnu:  TMenuWindow;
    Qst:  TQuestLog;
    procedure TogglePanel(id: LongInt);
    procedure OnInv(sender: TWidget);
    procedure OnChar(sender: TWidget);
    procedure OnOpts(sender: TWidget);
    procedure DragEnded(sender: TWidget);
    procedure OnCreateDone(speciesIdx, classIdx, bgIdx: LongInt; const name: String);
    procedure OnTradeConfirm(sender: TWidget);
    procedure OnMenuPick(action: LongInt);
  end;

var
  gTheme:   TSystem7Theme;
  gDesktop: TDesktop;
  gCanvas:  TGLCanvas;
  gWin:     TWindow;
  gHud:     THudPanel;
  gLog:     TLogPanel;
  gCompass: TCompassPanel;
  gCtl:     TUIController;
  gInvChange: TInvChangeProc;
  gCreateDone: TGameCreateProc;
  gTradeDone:  TTradeProc;
  gMenuPick:   TGameMenuProc;

procedure THudPanel.SetLines(const lines: array of String);
var
  i: LongInt;
begin
  SetLength(FLines, Length(lines));
  for i := 0 to High(lines) do FLines[i] := lines[i];
end;

procedure THudPanel.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  i, lh: LongInt;
begin
  r := AbsRect;
  lh := cv.TextHeight + 4;
  for i := 0 to High(FLines) do
    cv.DrawText(r.Left + 4, r.Top + 4 + i * lh, FLines[i], clBlack);
end;

procedure TLogPanel.SetLines(const lines: array of String);
var
  i: LongInt;
begin
  SetLength(FLines, Length(lines));
  for i := 0 to High(lines) do FLines[i] := lines[i];
end;

function TLogPanel.HitTest(const p: TPoint): TWidget;
begin
  { The log is a passive overlay; clicks fall through to whatever is behind it. }
  HitTest := nil;
end;

procedure TLogPanel.Draw(cv: TCanvas; theme: TTheme);
const
  clLogText   = TColor($FFEAE2C8);   { warm off-white }
  clLogShadow = TColor($C0000000);   { soft black, for contrast over any background }
var
  r: TRect;
  i, lh, x, y: LongInt;
begin
  r := AbsRect;
  lh := cv.TextHeight + 3;
  { Bottom-anchored: the last line sits at the foot of the panel. }
  for i := 0 to High(FLines) do begin
    x := r.Left;
    y := r.Bottom - (High(FLines) - i + 1) * lh;
    if y < r.Top then continue;
    cv.DrawText(x + 1, y + 1, FLines[i], clLogShadow);
    cv.DrawText(x, y, FLines[i], clLogText);
  end;
end;

procedure TCompassPanel.SetTarget(angle: Single; const caption: String; show: Boolean);
begin
  FAngle := angle; FLabel := caption; FShow := show;
end;

function TCompassPanel.HitTest(const p: TPoint): TWidget;
begin
  HitTest := nil;
end;

procedure TCompassPanel.Draw(cv: TCanvas; theme: TTheme);
const
  clArrow  = TColor($FFFFD24A);   { gold, matching the objective's glow }
  clShadow = TColor($C0000000);
  RAD = 32;

  procedure Dot(px, py: LongInt; col: TColor);
  begin
    cv.FillRect(Rect(px - 1, py - 1, px + 2, py + 2), col);
  end;

  procedure Stroke(x0, y0, ang, len: Single; col: TColor);
  var
    t: LongInt;
    sx, sy: Single;
  begin
    sx := Sin(ang); sy := -Cos(ang);   { ang 0 points up, clockwise }
    for t := 0 to Round(len) do
      Dot(Round(x0 + sx * t), Round(y0 + sy * t), col);
  end;

var
  r: TRect;
  cx, cy, x, y: LongInt;
  dirx, diry, hx, hy: Single;
begin
  if not FShow then exit;
  r := AbsRect;
  cx := (r.Left + r.Right) div 2;
  cy := r.Top + RAD + 10;
  dirx := Sin(FAngle); diry := -Cos(FAngle);

  { Shaft from a little behind centre out to the tip, drawn shadow then gold. }
  Stroke(cx - dirx * RAD * 0.4 + 1, cy - diry * RAD * 0.4 + 1, FAngle, RAD * 1.4, clShadow);
  Stroke(cx - dirx * RAD * 0.4,     cy - diry * RAD * 0.4,     FAngle, RAD * 1.4, clArrow);

  { Arrowhead: two strokes running back from the tip. }
  hx := cx + dirx * RAD; hy := cy + diry * RAD;
  Stroke(hx + 1, hy + 1, FAngle + 2.6, RAD * 0.45, clShadow);
  Stroke(hx + 1, hy + 1, FAngle - 2.6, RAD * 0.45, clShadow);
  Stroke(hx, hy, FAngle + 2.6, RAD * 0.45, clArrow);
  Stroke(hx, hy, FAngle - 2.6, RAD * 0.45, clArrow);

  { Objective name, centred beneath the dial. }
  x := cx - cv.TextWidth(FLabel) div 2;
  y := r.Top + 2 * RAD + 16;
  cv.DrawText(x + 1, y + 1, FLabel, clShadow);
  cv.DrawText(x, y, FLabel, clArrow);
end;

{ ---- TUIController ---- }

procedure TUIController.TogglePanel(id: LongInt);
var
  show: Boolean;
begin
  case id of
    0: begin
         show := not Inv.Visible;
         Inv.Visible := show;
         Equ.Visible := show;
         if show then begin
           gDesktop.BringToFront(Equ);
           gDesktop.BringToFront(Inv);
         end;
       end;
    1: begin
         show := not Chr.Visible;
         Chr.Visible := show;
         if show then gDesktop.BringToFront(Chr);
       end;
    2: begin
         show := not Opts.Visible;
         Opts.Visible := show;
         if show then gDesktop.BringToFront(Opts);
       end;
    3: begin
         show := not Qst.Visible;
         Qst.Visible := show;
         if show then gDesktop.BringToFront(Qst);
       end;
  end;
end;

procedure TUIController.OnInv(sender: TWidget);  begin TogglePanel(0); end;
procedure TUIController.OnChar(sender: TWidget); begin TogglePanel(1); end;
procedure TUIController.OnOpts(sender: TWidget); begin TogglePanel(2); end;

procedure TUIController.DragEnded(sender: TWidget);
{ A drag settled: read the new pack and worn layout back and hand it to the game. }
var
  tags: array[0 .. 127] of LongInt;
  pack: array of LongInt;
  n, i: LongInt;
begin
  if not Assigned(gInvChange) then exit;
  Inv.ReadTags(tags, n);
  SetLength(pack, n);
  for i := 0 to n - 1 do pack[i] := tags[i];
  gInvChange(pack, Equ.WornTag(bsMainHand), Equ.WornTag(bsChest),
             Equ.WornTag(bsOffHand));
end;

procedure TUIController.OnCreateDone(speciesIdx, classIdx, bgIdx: LongInt;
  const name: String);
begin
  if Assigned(gCreateDone) then gCreateDone(speciesIdx, classIdx, bgIdx, name);
  if Crt <> nil then Crt.Visible := False;
end;

procedure TUIController.OnTradeConfirm(sender: TWidget);
{ Read the staged piles off the window and hand them to the game to settle. }
var
  give, take: array[0 .. 127] of LongInt;
  giveList, takeList: array of LongInt;
  ng, nt, i: LongInt;
begin
  if not Assigned(gTradeDone) then exit;
  Trd.CollectGive(give, ng);
  Trd.CollectTake(take, nt);
  SetLength(giveList, ng);
  for i := 0 to ng - 1 do giveList[i] := give[i];
  SetLength(takeList, nt);
  for i := 0 to nt - 1 do takeList[i] := take[i];
  gTradeDone(giveList, takeList);
end;

procedure TUIController.OnMenuPick(action: LongInt);
begin
  if Assigned(gMenuPick) then gMenuPick(action);
end;

{ Read a CFN font file into memory and hand it to the canvas. A missing or
  malformed file is not fatal: the canvas keeps its built-in font. }
procedure LoadUIFont(const path: String);
var
  f: File;
  buf: array of Byte;
  n: LongInt;
begin
  if gCanvas = nil then exit;
  if not FileExists(path) then exit;
  AssignFile(f, path);
  Reset(f, 1);
  n := FileSize(f);
  if n > 0 then begin
    SetLength(buf, n);
    BlockRead(f, buf[0], n);
    if not gCanvas.LoadFont(buf[0], n) then
      writeln(StdErr, 'gameui: ', path, ' is not a valid font');
  end;
  CloseFile(f);
end;

procedure GameUIInit(viewW, viewH: LongInt);
var
  b: TButton;
begin
  gTheme := TSystem7Theme.Create;
  gDesktop := TDesktop.Create(gTheme, viewW, viewH);
  gCanvas := TGLCanvas.Create(viewW, viewH);
  LoadUIFont('content/fonts/ui.cfn');

  { status window: the live HUD lines, then a row of panel-toggle buttons }
  gWin := TWindow.Create(gDesktop, UIStr('win_status'), [wfClose, wfDrag, wfZoom], 12, 12, 250, 240);
  gHud := THudPanel.Create(gWin.Content);
  gHud.SetBounds(0, 0, 250, 180);

  { Transparent message log along the lower-left of the view, over the diorama. }
  gLog := TLogPanel.Create(gDesktop);
  gLog.SetBounds(16, viewH - 150, 16 + 520, viewH - 14);

  { Transparent objective compass in the upper-right. }
  gCompass := TCompassPanel.Create(gDesktop);
  gCompass.SetBounds(viewW - 150, 14, viewW - 14, 150);

  gCtl := TUIController.Create;
  b := TButton.Create(gWin.Content, UIStr('btn_inv'),  6, 186, 72, 22);  b.OnClick := @gCtl.OnInv;
  b := TButton.Create(gWin.Content, UIStr('btn_char'), 86, 186, 72, 22); b.OnClick := @gCtl.OnChar;
  b := TButton.Create(gWin.Content, UIStr('btn_opts'), 166, 186, 72, 22); b.OnClick := @gCtl.OnOpts;

  { the toggle panels, created hidden and shown on demand }
  gCtl.Inv  := TInventoryWindow.Create(gDesktop, 300, 40);
  gCtl.Equ  := TEquipmentWindow.Create(gDesktop, 580, 40);
  gCtl.Chr  := TCharacterSheet.Create(gDesktop, 300, 330);
  gCtl.Opts := TOptionsWindow.Create(gDesktop, 600, 330);
  gCtl.Trd  := TTradeWindow.Create(gDesktop, 280, 70);
  gCtl.Trd.OnConfirm := @gCtl.OnTradeConfirm;
  gCtl.Mnu  := TMenuWindow.Create(gDesktop, 420, 300);
  gCtl.Mnu.OnPick := @gCtl.OnMenuPick;
  gCtl.Qst  := TQuestLog.Create(gDesktop, 600, 40);
  gCtl.Inv.Visible := False;
  gCtl.Equ.Visible := False;
  gCtl.Chr.Visible := False;
  gCtl.Opts.Visible := False;
  gCtl.Trd.Visible := False;
  gCtl.Mnu.Visible := False;
  gCtl.Qst.Visible := False;
  gDesktop.OnDragEnd := @gCtl.DragEnded;

  gDesktop.BringToFront(gWin);
end;

procedure GameUITogglePanel(id: LongInt);
begin
  if gCtl <> nil then gCtl.TogglePanel(id);
end;

procedure GameUISetStatus(const lines: array of String);
begin
  if gHud <> nil then gHud.SetLines(lines);
end;

procedure GameUISetLog(const lines: array of String);
begin
  if gLog <> nil then gLog.SetLines(lines);
end;

procedure GameUISetCompass(angle: Single; const caption: String; show: Boolean);
begin
  if gCompass <> nil then gCompass.SetTarget(angle, caption, show);
end;

function GameUIItemCat(const kind: String): LongInt;
begin
  if kind = 'weapon' then GameUIItemCat := CAT_WEAPON
  else if kind = 'armor' then GameUIItemCat := CAT_ARMOR
  else if kind = 'shield' then GameUIItemCat := CAT_SHIELD
  else if kind = 'potion' then GameUIItemCat := CAT_POTION
  else GameUIItemCat := CAT_MISC;
end;

procedure GameUISetInventory(const items: array of TUIItem);
var
  i: LongInt;
begin
  if gCtl = nil then exit;
  gCtl.Inv.Clear;
  for i := 0 to High(items) do
    gCtl.Inv.Add(items[i].Name, items[i].Cat, TColor(items[i].Color),
                 items[i].Glyph, items[i].Tag);
end;

procedure SetWornSlot(s: TBodySlot; const it: TUIItem);
var
  tile: TDragItem;
begin
  if it.Tag < 0 then
    gCtl.Equ.SetWorn(s, nil)
  else begin
    tile := TDragItem.Create(it.Name, it.Cat, TColor(it.Color), it.Glyph);
    tile.Tag := it.Tag;
    gCtl.Equ.SetWorn(s, tile);
  end;
end;

procedure GameUISetWorn(const weapon, armor, shield: TUIItem);
begin
  if gCtl = nil then exit;
  SetWornSlot(bsMainHand, weapon);
  SetWornSlot(bsChest, armor);
  SetWornSlot(bsOffHand, shield);
end;

procedure GameUISetCharStats(const lines: array of String);
begin
  if gCtl <> nil then gCtl.Chr.SetStats(lines);
end;

procedure GameUISetQuests(const lines: array of String);
begin
  if gCtl <> nil then gCtl.Qst.SetLines(lines);
end;

procedure GameUISetInvChange(cb: TInvChangeProc);
begin
  gInvChange := cb;
end;

procedure GameUIInitCreate(const spNames, clNames: array of String;
  const clIdx: array of LongInt; const bgNames, names: array of String;
  defSp, defCl, defBg: LongInt);
begin
  if gCtl = nil then exit;
  gCtl.Crt := TCharCreateWindow.Create(gDesktop, 340, 250);
  gCtl.Crt.Setup(spNames, clNames, clIdx, bgNames, names, defSp, defCl, defBg);
  gCtl.Crt.OnDone := @gCtl.OnCreateDone;
  gCtl.Crt.Visible := False;
end;

procedure GameUIShowCreate;
begin
  if (gCtl <> nil) and (gCtl.Crt <> nil) then begin
    gCtl.Crt.Visible := True;
    gDesktop.BringToFront(gCtl.Crt);
  end;
end;

procedure GameUISetCreateDone(cb: TGameCreateProc);
begin
  gCreateDone := cb;
end;

procedure GameUIShowMenu(const heading: String; const lines, labels: array of String;
  const actions: array of LongInt);
begin
  if (gCtl = nil) or (gCtl.Mnu = nil) then exit;
  gCtl.Mnu.SetMenu(heading, lines, labels, actions);
  gCtl.Mnu.Visible := True;
  gDesktop.BringToFront(gCtl.Mnu);
end;

procedure GameUIHideMenu;
begin
  if (gCtl <> nil) and (gCtl.Mnu <> nil) then gCtl.Mnu.Visible := False;
end;

function GameUIMenuShown: Boolean;
begin
  GameUIMenuShown := (gCtl <> nil) and (gCtl.Mnu <> nil) and gCtl.Mnu.Visible;
end;

procedure GameUISetMenuPick(cb: TGameMenuProc);
begin
  gMenuPick := cb;
end;

function ToTradeItems(const src: array of TUIItem): TTradeArray;
var
  i: LongInt;
begin
  Result := nil;
  SetLength(Result, Length(src));
  for i := 0 to High(src) do begin
    Result[i].Name  := src[i].Name;
    Result[i].Price := src[i].Price;
    Result[i].Tag   := src[i].Tag;
    Result[i].Color := TColor(src[i].Color);
  end;
end;

procedure GameUIOpenTrade(const title: String;
  const stock, pack: array of TUIItem; gold: LongInt);
begin
  if gCtl = nil then exit;
  gCtl.Trd.SetDeal(title, ToTradeItems(stock), ToTradeItems(pack), gold);
  gCtl.Trd.Visible := True;
  gDesktop.BringToFront(gCtl.Trd);
end;

procedure GameUICloseTrade;
begin
  if gCtl <> nil then gCtl.Trd.Visible := False;
end;

function GameUITradeOpen: Boolean;
begin
  GameUITradeOpen := (gCtl <> nil) and gCtl.Trd.Visible;
end;

procedure GameUISetTradeDone(cb: TTradeProc);
begin
  gTradeDone := cb;
end;

procedure GameUISetCharIdentity(const name, klass, species: String);
begin
  if gCtl <> nil then gCtl.Chr.SetIdentity(name, klass, species);
end;

procedure GameUIMouse(kind, x, y, button, wheel: LongInt);
var
  e: TUIEvent;
begin
  if gDesktop = nil then exit;
  FillChar(e, SizeOf(e), 0);
  e.Pos := Pt(x, y);
  e.Button := button;
  e.Wheel := wheel;
  case kind of
    0: e.Kind := ekMouseDown;
    1: e.Kind := ekMouseUp;
    2: e.Kind := ekMouseMove;
    3: e.Kind := ekMouseWheel;
  else exit;
  end;
  gDesktop.Dispatch(e);
end;

procedure GameUIRender;
begin
  if gCanvas = nil then exit;
  gCanvas.BeginFrame;
  gDesktop.PaintAll(gCanvas);
  gCanvas.EndFrame;
end;

procedure GameUIFree;
begin
  if gDesktop <> nil then begin gDesktop.Free; gDesktop := nil; end;
  if gCtl <> nil then begin gCtl.Free; gCtl := nil; end;
  if gCanvas <> nil then begin gCanvas.Free; gCanvas := nil; end;
  if gTheme <> nil then begin gTheme.Free; gTheme := nil; end;
end;

end.
