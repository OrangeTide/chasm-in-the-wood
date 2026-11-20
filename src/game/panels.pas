unit panels;
{ Game interface panels built on the gui toolkit: a multi-page inventory, an        }
{ equipment paperdoll, a character sheet, and an options window. They add no new     }
{ mechanism; each composes the core widgets. Contents are placeholders until the     }
{ entity and item systems land, so the panels can be wired to real data later.      }

{$mode objfpc}{$H+}

interface

uses
  sysutils, gui;

const
  { Default volume percentages: the options sliders' initial values and the audio
    backend's startup volumes. The main program reads these so the two agree. }
  OPT_MUSIC_DEFAULT = 70;
  OPT_SFX_DEFAULT   = 90;

  { Item category bits, used as slot accept masks. }
  CAT_WEAPON = 1;
  CAT_SHIELD = 2;
  CAT_HELMET = 4;
  CAT_ARMOR  = 8;
  CAT_BOOTS  = 16;
  CAT_GLOVES = 32;
  CAT_RING   = 64;
  CAT_AMULET = 128;
  CAT_LEGS   = 256;
  CAT_POTION = 512;
  CAT_MISC   = 1024;

type
  { ---- multi-page inventory ---- }
  TInventoryWindow = class(TWindow)
  private
    FTabs:  TTabBar;
    FPages: array of TItemGrid;
    procedure HandleTab(index: LongInt);
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    procedure ShowPage(i: LongInt);
    function  Page(i: LongInt): TItemGrid;
    { Empty every slot, freeing the item tiles. }
    procedure Clear;
    { Place one item tile in the next free slot, filling pages in order. False when
      every slot is taken. }
    function  Add(const name: String; cat: LongInt; color: TColor;
                  glyph: Char; tag: LongInt): Boolean;
    { Collect the payload tags of the filled slots, in slot order. }
    procedure ReadTags(out tags: array of LongInt; out n: LongInt);
  end;

  { ---- equipment paperdoll ---- }
  TBodySlot = (bsHead, bsAmulet, bsChest, bsMainHand, bsOffHand,
               bsGloves, bsLegs, bsFeet, bsRing);

  TPaperdoll = class(TWidget)
  private
    FSlots: array[TBodySlot] of TItemSlot;
  public
    constructor Create(AParent: TWidget; l, t, w, h: LongInt);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
    procedure PlaceSlot(s: TBodySlot; l, t, sz, accept: LongInt);
    function  Slot(s: TBodySlot): TItemSlot;
  end;

  TEquipmentWindow = class(TWindow)
  private
    FDoll: TPaperdoll;
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    function Doll: TPaperdoll;
    { Put an item tile in a worn slot, freeing whatever it held; nil empties it. }
    procedure SetWorn(s: TBodySlot; it: TDragItem);
    { The payload tag of the worn slot, or -1 when empty. }
    function  WornTag(s: TBodySlot): LongInt;
  end;

  { ---- character sheet: flavour header, live stat lines, a scrolling skill list ---- }
  TCharacterSheet = class(TWindow)
  private
    FName, FClass, FSpecies: TLabel;
    FStats: array of TLabel;
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    { Replace the identity header (name, class, species). }
    procedure SetIdentity(const name, klass, species: String);
    { Replace the live stat lines (health, armour, attack, and the like). }
    procedure SetStats(const lines: array of String);
  end;

  { The quest log: a scrolling list of the active quests and their current objectives,
    completed quests, and the journal, pushed as plain text lines by the game. }
  TQuestLog = class(TWindow)
  private
    FScroll: TScrollView;
    FLines:  array of TLabel;
  public
    constructor Create(AParent: TWidget; l, t: LongInt);
    { Replace the shown lines. Lines past the pool are dropped. }
    procedure SetLines(const lines: array of String);
  end;

  { Fired when a menu or dialogue button is clicked, carrying that button's action tag or
    response index. }
  TMenuPickProc = procedure(action: LongInt) of object;

  { The narration pane of the dialogue window: one block of text, word-wrapped to the
    pane width and drawn from the top left. }
  TDialogPane = class(TWidget)
  private
    FText: String;
  public
    procedure SetText(const s: String);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { A conversation window: the speaker's line in the title bar, their current narration,
    and a stack of response buttons. Picking a button hands its response index (its Tag)
    back through OnPick. The close box leaves the talk. }
  TDialogWindow = class(TWindow)
  private
    FPane: TDialogPane;
    FButtons: array of TButton;
    procedure OnButton(sender: TWidget);
  public
    OnPick: TMenuPickProc;
    constructor Create(AParent: TWidget; l, t: LongInt);
    { Show a node: the speaker in the title, the narration, and one button per response.
      labels and picks run in step; picks[i] is the response index handed to OnPick. }
    procedure SetNode(const speaker, text: String;
                      const labels: array of String; const picks: array of LongInt);
  end;

  { ---- new-adventurer creation ---- }
  { Fired on Begin with the chosen species, class, and background content indices and
    the name. }
  TCreateDoneProc = procedure(speciesIdx, classIdx, bgIdx: LongInt;
                              const name: String) of object;

  TCharCreateWindow = class(TWindow)
  private
    FSpNames:  array of String;   { all species names, in content order }
    FClNames:  array of String;   { the offered class names }
    FClIdx:    array of LongInt;  { content index behind each offered class }
    FBgNames:  array of String;   { all background names, in content order }
    FNames:    array of String;   { the random name pool }
    FSp, FCl:  LongInt;           { chosen species and class content indices }
    FBg:       LongInt;           { chosen background content index }
    FNameI:    LongInt;           { chosen name pool index }
    FSpBtn, FClBtn, FBgBtn, FNameBtn, FBeginBtn: TButton;
    procedure OnSpecies(sender: TWidget);
    procedure OnClass(sender: TWidget);
    procedure OnBackground(sender: TWidget);
    procedure OnName(sender: TWidget);
    procedure OnBegin(sender: TWidget);
    procedure PickSpecies(index: LongInt);
    procedure PickClass(index: LongInt);
    procedure PickBackground(index: LongInt);
    procedure Refresh;
  public
    OnDone: TCreateDoneProc;
    constructor Create(AParent: TWidget; l, t: LongInt);
    { Fill the pickers. Class names and their content indices run in step; background
      names run in content order. defSp, defCl, and defBg are the initial species,
      class, and background content indices. }
    procedure Setup(const spNames, clNames: array of String;
                    const clIdx: array of LongInt;
                    const bgNames, names: array of String;
                    defSp, defCl, defBg: LongInt);
  end;

  { Applies a 0..1 volume to an audio channel. The main program wires it to the
    audio backend; it is left nil in the tests and anywhere the GL-free panels
    unit is used without audio, so panels pulls in no audio backend. }
  TVolumeProc = procedure(v: Single);

  { ---- options: live music and effects volume, plus placeholder toggles ---- }
  TOptionsWindow = class(TWindow)
  private
    FVsync, FCamera: TButton;
    FMusic, FSfx: TSlider;
    FMusicLbl, FSfxLbl: TLabel;
    FVsyncOn: Boolean;
    FCam: LongInt;
    procedure OnVsync(sender: TWidget);
    procedure OnCamera(sender: TWidget);
    procedure OnMusic(sender: TWidget);
    procedure OnSfx(sender: TWidget);
  public
    { Wired by the main program to the audio volume setters, applied live as the
      sliders move. Left nil elsewhere. }
    MusicVol: TVolumeProc;
    SfxVol:   TVolumeProc;
    constructor Create(AParent: TWidget; l, t: LongInt);
  end;

  { ---- trade window: barter with a town shop ---- }
  { One row of a trade column: a shop item to take, or a pack item to give. For a shop
    row Price is the buy price and Tag the content item index; for a pack row Price is
    the sell price and Tag the pack slot. }
  TTradeItem = record
    Name:  String;
    Price: LongInt;
    Tag:   LongInt;
    Color: TColor;
  end;
  TTradeArray = array of TTradeItem;

  { The self-drawn body: two columns (the shop's stock to buy, the pack to sell), each
    item a clickable row that toggles into the deal. The running balance is the sell
    value staged from the pack minus the buy value staged from the stock. }
  TTradePane = class(TWidget)
  private
    FHeader: String;
    FStock, FPack: array of TTradeItem;
    FTakeOn, FGiveOn: array of Boolean;
    FGold: LongInt;
    { Layout cached by Draw (screen coordinates), read back by OnMouseDown. }
    FLytLX, FLytRX, FLytColW, FLytTop, FLytMax: LongInt;
    function RowH: LongInt;
    function ColW(const r: TRect): LongInt;
    function MaxRows(const r: TRect; cv: TCanvas): LongInt;
    function ListTop(const r: TRect): LongInt;
  public
    procedure SetDeal(const header: String; const stock, pack: array of TTradeItem;
                      gold: LongInt);
    function  Balance: LongInt;
    procedure CollectGive(out tags: array of LongInt; out n: LongInt);
    procedure CollectTake(out items: array of LongInt; out n: LongInt);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
    procedure OnMouseDown(var e: TUIEvent); override;
  end;

  TTradeWindow = class(TWindow)
  private
    FPane: TTradePane;
    FConfirm, FDone: TButton;
    procedure OnConfirmClick(sender: TWidget);
    procedure OnDoneClick(sender: TWidget);
  public
    { Fired when the player confirms a deal; the owner reads it back with the collectors
      below, settles it, and either refreshes or closes the window. }
    OnConfirm: TNotifyProc;
    constructor Create(AParent: TWidget; l, t: LongInt);
    procedure SetDeal(const header: String; const stock, pack: array of TTradeItem;
                      gold: LongInt);
    procedure CollectGive(out tags: array of LongInt; out n: LongInt);
    procedure CollectTake(out items: array of LongInt; out n: LongInt);
  end;

  { ---- front-end menu: the title, victory, and death screens ---- }
  { A centered column of text lines drawn over the window body. }
  TMenuPane = class(TWidget)
  private
    FLines: array of String;
  public
    procedure SetLines(const lines: array of String);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { A centered, undismissable window with a heading, a few body lines, and a vertical
    stack of action buttons. One instance serves the title, victory, and death screens,
    reconfigured by SetMenu. }
  TMenuWindow = class(TWindow)
  private
    FPane: TMenuPane;
    FButtons: array of TButton;
    procedure OnButton(sender: TWidget);
  public
    OnPick: TMenuPickProc;
    constructor Create(AParent: TWidget; w, h: LongInt);
    { Set the heading (the title bar), the centered body lines, and the action buttons:
      labels paired with the action tags handed back through OnPick. }
    procedure SetMenu(const heading: String; const lines: array of String;
                      const labels: array of String; const actions: array of LongInt);
  end;

implementation

uses
  uitext;

{ ---- TInventoryWindow ---- }

constructor TInventoryWindow.Create(AParent: TWidget; l, t: LongInt);
var
  i: LongInt;
begin
  inherited Create(AParent, UIStr('win_inventory'), [wfClose, wfDrag, wfZoom], l, t, 264, 230);
  FTabs := TTabBar.Create(Content, 6, 4, 58, 20);
  FTabs.OnChange := @HandleTab;
  SetLength(FPages, 4);
  for i := 0 to 3 do begin
    FTabs.AddTab('BAG' + IntToStr(i + 1));
    { cols, rows, accept, pitch, l, t }
    FPages[i] := TItemGrid.Create(Content, 6, 5, 0, 32, 6, 28);
    FPages[i].Visible := (i = 0);
  end;
end;

procedure TInventoryWindow.HandleTab(index: LongInt);
begin
  ShowPage(index);
end;

procedure TInventoryWindow.ShowPage(i: LongInt);
var
  k: LongInt;
begin
  for k := 0 to High(FPages) do FPages[k].Visible := (k = i);
end;

function TInventoryWindow.Page(i: LongInt): TItemGrid;
begin
  Page := FPages[i];
end;

procedure TInventoryWindow.Clear;
var
  p, col, row: LongInt;
  g: TItemGrid;
  slot: TItemSlot;
begin
  for p := 0 to High(FPages) do begin
    g := FPages[p];
    for row := 0 to g.Rows - 1 do
      for col := 0 to g.Cols - 1 do begin
        slot := g.SlotAt(col, row);
        if slot.Item <> nil then begin
          slot.Item.Free;
          slot.Item := nil;
        end;
      end;
  end;
end;

function TInventoryWindow.Add(const name: String; cat: LongInt; color: TColor;
  glyph: Char; tag: LongInt): Boolean;
var
  p, col, row: LongInt;
  g: TItemGrid;
  slot: TItemSlot;
  it: TDragItem;
begin
  for p := 0 to High(FPages) do begin
    g := FPages[p];
    for row := 0 to g.Rows - 1 do
      for col := 0 to g.Cols - 1 do begin
        slot := g.SlotAt(col, row);
        if slot.Item = nil then begin
          it := TDragItem.Create(name, cat, color, glyph);
          it.Tag := tag;
          slot.Item := it;
          exit(True);
        end;
      end;
  end;
  Add := False;
end;

procedure TInventoryWindow.ReadTags(out tags: array of LongInt; out n: LongInt);
var
  p, col, row: LongInt;
  g: TItemGrid;
  slot: TItemSlot;
begin
  n := 0;
  for p := 0 to High(FPages) do begin
    g := FPages[p];
    for row := 0 to g.Rows - 1 do
      for col := 0 to g.Cols - 1 do begin
        slot := g.SlotAt(col, row);
        if (slot.Item <> nil) and (n < Length(tags)) then begin
          tags[n] := slot.Item.Tag;
          Inc(n);
        end;
      end;
  end;
end;

{ ---- TPaperdoll ---- }

constructor TPaperdoll.Create(AParent: TWidget; l, t, w, h: LongInt);
var
  s: TBodySlot;
begin
  inherited Create(AParent);
  SetBounds(l, t, l + w, t + h);
  for s := Low(TBodySlot) to High(TBodySlot) do FSlots[s] := nil;
end;

procedure TPaperdoll.PlaceSlot(s: TBodySlot; l, t, sz, accept: LongInt);
begin
  FSlots[s] := TItemSlot.Create(Self, accept, l, t, sz);
end;

function TPaperdoll.Slot(s: TBodySlot): TItemSlot;
begin
  Slot := FSlots[s];
end;

procedure TPaperdoll.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  cx, cy: LongInt;
  skin, line: TColor;
begin
  r := AbsRect;
  cv.FillRect(r, clWhite);
  skin := TColor($FFD9C9A8);
  line := TColor($FF8A764F);
  cx := (r.Left + r.Right) div 2;
  cy := r.Top + 20;
  cv.FillRect(Rect(cx - 12, cy, cx + 12, cy + 22), skin);        { head }
  cv.FrameRect(Rect(cx - 12, cy, cx + 12, cy + 22), line);
  cv.FillRect(Rect(cx - 20, cy + 24, cx + 20, cy + 70), skin);   { torso }
  cv.FrameRect(Rect(cx - 20, cy + 24, cx + 20, cy + 70), line);
  cv.FillRect(Rect(cx - 34, cy + 26, cx - 20, cy + 64), skin);   { left arm }
  cv.FrameRect(Rect(cx - 34, cy + 26, cx - 20, cy + 64), line);
  cv.FillRect(Rect(cx + 20, cy + 26, cx + 34, cy + 64), skin);   { right arm }
  cv.FrameRect(Rect(cx + 20, cy + 26, cx + 34, cy + 64), line);
  cv.FillRect(Rect(cx - 16, cy + 70, cx - 2, cy + 118), skin);   { left leg }
  cv.FrameRect(Rect(cx - 16, cy + 70, cx - 2, cy + 118), line);
  cv.FillRect(Rect(cx + 2, cy + 70, cx + 16, cy + 118), skin);   { right leg }
  cv.FrameRect(Rect(cx + 2, cy + 70, cx + 16, cy + 118), line);
end;

{ ---- TEquipmentWindow ---- }

constructor TEquipmentWindow.Create(AParent: TWidget; l, t: LongInt);
begin
  inherited Create(AParent, UIStr('win_equipment'), [wfClose, wfDrag], l, t, 210, 268);
  FDoll := TPaperdoll.Create(Content, 0, 0, 206, 240);
  { Slots flank the figure: four down the left, five down the right. }
  FDoll.PlaceSlot(bsHead,     6, 6,   30, CAT_HELMET);
  FDoll.PlaceSlot(bsChest,    6, 46,  30, CAT_ARMOR);
  FDoll.PlaceSlot(bsLegs,     6, 86,  30, CAT_LEGS);
  FDoll.PlaceSlot(bsFeet,     6, 126, 30, CAT_BOOTS);
  FDoll.PlaceSlot(bsMainHand, 170, 6,   30, CAT_WEAPON);
  FDoll.PlaceSlot(bsOffHand,  170, 46,  30, CAT_SHIELD);
  FDoll.PlaceSlot(bsGloves,   170, 86,  30, CAT_GLOVES);
  FDoll.PlaceSlot(bsRing,     170, 126, 30, CAT_RING);
  FDoll.PlaceSlot(bsAmulet,   170, 166, 30, CAT_AMULET);
end;

function TEquipmentWindow.Doll: TPaperdoll;
begin
  Doll := FDoll;
end;

procedure TEquipmentWindow.SetWorn(s: TBodySlot; it: TDragItem);
var
  slot: TItemSlot;
begin
  slot := FDoll.Slot(s);
  if slot = nil then exit;
  if slot.Item <> nil then slot.Item.Free;
  slot.Item := it;
end;

function TEquipmentWindow.WornTag(s: TBodySlot): LongInt;
var
  slot: TItemSlot;
begin
  slot := FDoll.Slot(s);
  if (slot <> nil) and (slot.Item <> nil) then WornTag := slot.Item.Tag
  else WornTag := -1;
end;

{ ---- TCharacterSheet ---- }

constructor TCharacterSheet.Create(AParent: TWidget; l, t: LongInt);
var
  sv: TScrollView;
  list: TWidget;
  i, y: LongInt;
  skills: TUIStrArray;
const
  STAT_LINES = 5;   { level/xp, health/armour, attack, two ability rows }
begin
  inherited Create(AParent, UIStr('win_character'), [wfClose, wfDrag], l, t, 300, 280);
  FName    := TLabel.Create(Content, UIStr('lbl_name'), 8, 8);
  FClass   := TLabel.Create(Content, UIStr('lbl_class'), 8, 24);
  FSpecies := TLabel.Create(Content, UIStr('lbl_species'), 8, 40);
  { Live stat lines, filled by SetStats; created empty so the panel reads sensibly
    before the game pushes its first update. }
  SetLength(FStats, STAT_LINES);
  for i := 0 to STAT_LINES - 1 do
    FStats[i] := TLabel.Create(Content, '', 8, 60 + i * 16);
  TLabel.Create(Content, UIStr('lbl_skills'), 8, 150);
  skills := UIStrList('sheet_skills');
  sv := TScrollView.Create(Content, 8, 166, 276, 84);
  list := TWidget.Create(sv);
  y := 4;
  for i := 0 to High(skills) do begin
    TLabel.Create(list, skills[i], 6, y);
    y := y + 16;
  end;
  sv.SetContentSize(y + 4);
end;

procedure TCharacterSheet.SetIdentity(const name, klass, species: String);
begin
  FName.Caption := UIStrFmt('sheet_name', [name]);
  FClass.Caption := UIStrFmt('sheet_class', [klass]);
  FSpecies.Caption := UIStrFmt('sheet_species', [species]);
end;

procedure TCharacterSheet.SetStats(const lines: array of String);
var
  i: LongInt;
begin
  for i := 0 to High(FStats) do
    if i <= High(lines) then FStats[i].Caption := lines[i]
    else FStats[i].Caption := '';
end;

{ ---- quest log ---- }

constructor TQuestLog.Create(AParent: TWidget; l, t: LongInt);
const
  MAXLINES = 32;   { pool size; the log is small and scrolls if it ever grows past this }
var
  list: TWidget;
  i: LongInt;
begin
  inherited Create(AParent, UIStr('win_quests'), [wfClose, wfDrag], l, t, 420, 300);
  FScroll := TScrollView.Create(Content, 8, 8, 404, 284);
  list := TWidget.Create(FScroll);
  SetLength(FLines, MAXLINES);
  for i := 0 to MAXLINES - 1 do
    FLines[i] := TLabel.Create(list, '', 6, 4 + i * 16);
  FScroll.SetContentSize(4 + MAXLINES * 16);
end;

procedure TQuestLog.SetLines(const lines: array of String);
var
  i, n: LongInt;
begin
  n := Length(lines);
  for i := 0 to High(FLines) do
    if i < n then FLines[i].Caption := lines[i]
    else FLines[i].Caption := '';
  if n < 1 then n := 1;
  if n > Length(FLines) then n := Length(FLines);
  FScroll.SetContentSize(4 + n * 16);
end;

{ ---- TDialogPane ---- }

procedure TDialogPane.SetText(const s: String);
begin
  FText := s;
end;

procedure TDialogPane.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  src, cur, word: String;
  i, y, lh, maxw: LongInt;

  procedure Emit(const ln: String);
  begin
    cv.DrawText(r.Left, y, ln, clBlack);
    Inc(y, lh);
  end;

begin
  r := AbsRect;
  lh := cv.TextHeight + 4;
  y := r.Top;
  maxw := RectW(r);
  cur := '';
  word := '';
  src := FText + ' ';           { a trailing space flushes the final word }
  for i := 1 to Length(src) do
    if src[i] = ' ' then begin
      if word <> '' then begin
        if cur = '' then
          cur := word
        else if cv.TextWidth(cur + ' ' + word) <= maxw then
          cur := cur + ' ' + word
        else begin
          Emit(cur);
          cur := word;
        end;
        word := '';
      end;
    end else
      word := word + src[i];
  if cur <> '' then Emit(cur);
end;

{ ---- TDialogWindow ---- }

const
  DLG_MAXBTN = 6;
  DLG_W      = 460;
  DLG_H      = 320;
  DLG_BTNH   = 26;
  DLG_BTNGAP = 6;

constructor TDialogWindow.Create(AParent: TWidget; l, t: LongInt);
var
  i: LongInt;
begin
  inherited Create(AParent, UIStr('win_talk'), [wfClose, wfDrag], l, t, DLG_W, DLG_H);
  FPane := TDialogPane.Create(Content);
  SetLength(FButtons, DLG_MAXBTN);
  for i := 0 to DLG_MAXBTN - 1 do begin
    FButtons[i] := TButton.Create(Content, '', 0, 0, 10, DLG_BTNH);
    FButtons[i].OnClick := @OnButton;
    FButtons[i].Visible := False;
  end;
end;

procedure TDialogWindow.OnButton(sender: TWidget);
begin
  if Assigned(OnPick) then OnPick((sender as TButton).Tag);
end;

procedure TDialogWindow.SetNode(const speaker, text: String;
  const labels: array of String; const picks: array of LongInt);
var
  bw, th, cw, ch, n, blockH, btnTop, bwid, i: LongInt;
begin
  Title := speaker;
  FPane.SetText(text);
  n := Length(labels);
  if n > DLG_MAXBTN then n := DLG_MAXBTN;

  bw := Root.Theme.BorderWidth;
  th := Root.Theme.TitleBarHeight;
  cw := RectW(FBounds) - 2 * bw;
  ch := RectH(FBounds) - th - bw;

  blockH := n * DLG_BTNH + (n - 1) * DLG_BTNGAP;
  btnTop := ch - 10 - blockH;
  bwid := cw - 16;

  { Narration fills the space above the button block. }
  FPane.SetBounds(8, 8, cw - 8, btnTop - DLG_BTNGAP);

  for i := 0 to DLG_MAXBTN - 1 do
    if i < n then begin
      FButtons[i].Caption := labels[i];
      FButtons[i].Tag := picks[i];
      FButtons[i].SetBounds(8, btnTop + i * (DLG_BTNH + DLG_BTNGAP),
                            8 + bwid, btnTop + i * (DLG_BTNH + DLG_BTNGAP) + DLG_BTNH);
      FButtons[i].Visible := True;
    end else
      FButtons[i].Visible := False;
end;

{ ---- TOptionsWindow ---- }

constructor TOptionsWindow.Create(AParent: TWidget; l, t: LongInt);
begin
  inherited Create(AParent, UIStr('win_options'), [wfClose, wfDrag], l, t, 212, 206);
  FVsyncOn := True; FCam := 1;
  { Music and effects volume: 0..100 percent, applied live through the hooks. The
    defaults match the audio backend's startup volumes (see datadir/chasm init). }
  FMusicLbl := TLabel.Create(Content, UIStrFmt('opt_music', [OPT_MUSIC_DEFAULT]), 12, 10);
  FMusic := TSlider.Create(Content, 12, 28, 186, 22, 0, 100, OPT_MUSIC_DEFAULT);
  FMusic.OnChange := @OnMusic;
  FSfxLbl := TLabel.Create(Content, UIStrFmt('opt_sfx', [OPT_SFX_DEFAULT]), 12, 60);
  FSfx := TSlider.Create(Content, 12, 78, 186, 22, 0, 100, OPT_SFX_DEFAULT);
  FSfx.OnChange := @OnSfx;
  FVsync := TButton.Create(Content, UIStr('opt_vsync_on'), 12, 110, 186, 24);
  FVsync.OnClick := @OnVsync;
  FCamera := TButton.Create(Content, UIStr('opt_cam_med'), 12, 140, 186, 24);
  FCamera.OnClick := @OnCamera;
end;

procedure TOptionsWindow.OnVsync(sender: TWidget);
begin
  FVsyncOn := not FVsyncOn;
  if FVsyncOn then FVsync.Caption := UIStr('opt_vsync_on')
  else FVsync.Caption := UIStr('opt_vsync_off');
end;

procedure TOptionsWindow.OnMusic(sender: TWidget);
begin
  FMusicLbl.Caption := UIStrFmt('opt_music', [FMusic.Value]);
  if Assigned(MusicVol) then MusicVol(FMusic.Value / 100.0);
end;

procedure TOptionsWindow.OnSfx(sender: TWidget);
begin
  FSfxLbl.Caption := UIStrFmt('opt_sfx', [FSfx.Value]);
  if Assigned(SfxVol) then SfxVol(FSfx.Value / 100.0);
end;

procedure TOptionsWindow.OnCamera(sender: TWidget);
begin
  FCam := (FCam + 1) mod 3;
  case FCam of
    0: FCamera.Caption := UIStr('opt_cam_near');
    1: FCamera.Caption := UIStr('opt_cam_med');
    2: FCamera.Caption := UIStr('opt_cam_far');
  end;
end;

{ ---- TCharCreateWindow ---- }

constructor TCharCreateWindow.Create(AParent: TWidget; l, t: LongInt);
begin
  inherited Create(AParent, UIStr('win_create'), [wfDrag], l, t, 444, 226);
  FSp := 0; FCl := 0; FBg := 0; FNameI := 0;
  TLabel.Create(Content, UIStr('create_head'), 10, 8);
  FNameBtn  := TButton.Create(Content, UIStr('lbl_name'),       10, 32, 424, 24);
  FNameBtn.OnClick := @OnName;
  FSpBtn    := TButton.Create(Content, UIStr('lbl_species'),    10, 62, 424, 24);
  FSpBtn.OnClick := @OnSpecies;
  FClBtn    := TButton.Create(Content, UIStr('lbl_class'),      10, 92, 424, 24);
  FClBtn.OnClick := @OnClass;
  FBgBtn    := TButton.Create(Content, UIStr('lbl_background'), 10, 122, 424, 24);
  FBgBtn.OnClick := @OnBackground;
  FBeginBtn := TButton.Create(Content, UIStr('create_begin'),  10, 158, 424, 28);
  FBeginBtn.OnClick := @OnBegin;
end;

procedure TCharCreateWindow.Setup(const spNames, clNames: array of String;
  const clIdx: array of LongInt; const bgNames, names: array of String;
  defSp, defCl, defBg: LongInt);
var
  i: LongInt;
begin
  SetLength(FSpNames, Length(spNames));
  for i := 0 to High(spNames) do FSpNames[i] := spNames[i];
  SetLength(FClNames, Length(clNames));
  for i := 0 to High(clNames) do FClNames[i] := clNames[i];
  SetLength(FClIdx, Length(clIdx));
  for i := 0 to High(clIdx) do FClIdx[i] := clIdx[i];
  SetLength(FBgNames, Length(bgNames));
  for i := 0 to High(bgNames) do FBgNames[i] := bgNames[i];
  SetLength(FNames, Length(names));
  for i := 0 to High(names) do FNames[i] := names[i];
  FSp := defSp; FCl := defCl; FBg := defBg; FNameI := 0;
  Refresh;
end;

procedure TCharCreateWindow.Refresh;
var
  i: LongInt;
  cn: String;
begin
  if (Length(FNames) > 0) and (FNameI >= 0) and (FNameI < Length(FNames)) then
    FNameBtn.Caption := UIStrFmt('create_name_lbl', [FNames[FNameI]])
  else
    FNameBtn.Caption := UIStr('create_name_none');
  if (FSp >= 0) and (FSp < Length(FSpNames)) then
    FSpBtn.Caption := UIStrFmt('create_species_lbl', [FSpNames[FSp]])
  else
    FSpBtn.Caption := UIStr('create_species_none');
  cn := '?';
  for i := 0 to High(FClIdx) do
    if FClIdx[i] = FCl then cn := FClNames[i];
  FClBtn.Caption := UIStrFmt('create_class_lbl', [cn]);
  if (FBg >= 0) and (FBg < Length(FBgNames)) then
    FBgBtn.Caption := UIStrFmt('create_background_lbl', [FBgNames[FBg]])
  else
    FBgBtn.Caption := UIStr('create_background_none');
end;

procedure TCharCreateWindow.OnSpecies(sender: TWidget);
var
  d: TDesktop;
begin
  d := Root;
  if d <> nil then
    d.ShowPopup(FSpNames, Pt(FSpBtn.AbsRect.Left, FSpBtn.AbsRect.Bottom),
                @PickSpecies);
end;

procedure TCharCreateWindow.OnClass(sender: TWidget);
var
  d: TDesktop;
begin
  d := Root;
  if d <> nil then
    d.ShowPopup(FClNames, Pt(FClBtn.AbsRect.Left, FClBtn.AbsRect.Bottom),
                @PickClass);
end;

procedure TCharCreateWindow.OnBackground(sender: TWidget);
var
  d: TDesktop;
begin
  d := Root;
  if d <> nil then
    d.ShowPopup(FBgNames, Pt(FBgBtn.AbsRect.Left, FBgBtn.AbsRect.Bottom),
                @PickBackground);
end;

procedure TCharCreateWindow.OnName(sender: TWidget);
begin
  if Length(FNames) = 0 then exit;
  FNameI := (FNameI + 1) mod Length(FNames);
  Refresh;
end;

procedure TCharCreateWindow.OnBegin(sender: TWidget);
var
  nm: String;
begin
  if (Length(FNames) > 0) and (FNameI >= 0) and (FNameI < Length(FNames)) then
    nm := FNames[FNameI]
  else
    nm := UIStr('name_vagrant');
  if Assigned(OnDone) then OnDone(FSp, FCl, FBg, nm);
end;

procedure TCharCreateWindow.PickSpecies(index: LongInt);
begin
  if (index >= 0) and (index < Length(FSpNames)) then FSp := index;
  Refresh;
end;

procedure TCharCreateWindow.PickClass(index: LongInt);
begin
  if (index >= 0) and (index < Length(FClIdx)) then FCl := FClIdx[index];
  Refresh;
end;

procedure TCharCreateWindow.PickBackground(index: LongInt);
{ Background names run in content order, so the popup index is the content index. }
begin
  if (index >= 0) and (index < Length(FBgNames)) then FBg := index;
  Refresh;
end;

{ ---- TTradePane ---- }

const
  clStageHi = TColor($FF3A5B8C);   { staged-row fill, a muted blue }
  clStageTx = TColor($FFFFFFFF);   { staged-row text }

function TTradePane.RowH: LongInt;
begin
  RowH := 20;
end;

function TTradePane.ColW(const r: TRect): LongInt;
begin
  ColW := (RectW(r) - 24) div 2;   { 8px gutters each side and a middle gap }
end;

function TTradePane.ListTop(const r: TRect): LongInt;
begin
  ListTop := r.Top + 8 + RowH;     { a header row, then the lists }
end;

function TTradePane.MaxRows(const r: TRect; cv: TCanvas): LongInt;
var
  foot: LongInt;
begin
  foot := r.Bottom - 34 - (cv.TextHeight + 2) * 2;   { button strip, then two footer lines }
  MaxRows := (foot - ListTop(r)) div RowH;
  if MaxRows < 0 then MaxRows := 0;
end;

procedure TTradePane.SetDeal(const header: String; const stock, pack: array of TTradeItem;
  gold: LongInt);
var
  i: LongInt;
begin
  FHeader := header;
  SetLength(FStock, Length(stock));
  SetLength(FTakeOn, Length(stock));
  for i := 0 to High(stock) do begin FStock[i] := stock[i]; FTakeOn[i] := False; end;
  SetLength(FPack, Length(pack));
  SetLength(FGiveOn, Length(pack));
  for i := 0 to High(pack) do begin FPack[i] := pack[i]; FGiveOn[i] := False; end;
  FGold := gold;
end;

function TTradePane.Balance: LongInt;
var
  i, b: LongInt;
begin
  b := 0;
  for i := 0 to High(FPack) do
    if FGiveOn[i] then Inc(b, FPack[i].Price);
  for i := 0 to High(FStock) do
    if FTakeOn[i] then Dec(b, FStock[i].Price);
  Balance := b;
end;

procedure TTradePane.CollectGive(out tags: array of LongInt; out n: LongInt);
var
  i: LongInt;
begin
  n := 0;
  for i := 0 to High(FPack) do
    if FGiveOn[i] and (n <= High(tags)) then begin tags[n] := FPack[i].Tag; Inc(n); end;
end;

procedure TTradePane.CollectTake(out items: array of LongInt; out n: LongInt);
var
  i: LongInt;
begin
  n := 0;
  for i := 0 to High(FStock) do
    if FTakeOn[i] and (n <= High(items)) then begin items[n] := FStock[i].Tag; Inc(n); end;
end;

procedure TTradePane.Draw(cv: TCanvas; theme: TTheme);
var
  r, row: TRect;
  cw, lx, rx, y, mr, bal, fy: LongInt;
  price: String;

  procedure Column(const col: array of TTradeItem; const on: array of Boolean;
    x: LongInt);
  var
    k, nameW: LongInt;
    tc: TColor;
    nm: String;
  begin
    for k := 0 to High(col) do begin
      if k >= mr then break;
      row := Rect(x, y + k * RowH, x + cw, y + k * RowH + RowH - 1);
      if on[k] then begin
        cv.FillRect(row, clStageHi);
        tc := clStageTx;
      end else
        tc := clBlack;
      price := IntToStr(col[k].Price);
      { Truncate the name so it never runs into the right-aligned price. }
      nameW := cw - 8 - cv.TextWidth(price) - 6;
      nm := col[k].Name;
      while (nm <> '') and (cv.TextWidth(nm) > nameW) do Delete(nm, Length(nm), 1);
      cv.DrawText(row.Left + 4, row.Top + 1, nm, tc);
      cv.DrawText(row.Right - 4 - cv.TextWidth(price), row.Top + 1, price, tc);
    end;
  end;

begin
  r := AbsRect;
  cv.FillRect(r, clParch);
  cw := ColW(r);
  lx := r.Left + 8;
  rx := r.Left + 8 + cw + 8;
  { Column headers: BUY over the shop's stock, SELL over the pack. }
  cv.DrawText(lx, r.Top + 4, UIStr('trade_buy'), clBlack);
  cv.DrawText(rx, r.Top + 4, UIStr('trade_sell'), clBlack);
  y := ListTop(r);
  mr := MaxRows(r, cv);
  { Cache the layout so a click can map to a row without a canvas. }
  FLytLX := lx; FLytRX := rx; FLytColW := cw; FLytTop := y; FLytMax := mr;
  Column(FStock, FTakeOn, lx);
  Column(FPack, FGiveOn, rx);
  { Footer: the running balance and the resulting purse. }
  bal := Balance;
  fy := r.Bottom - 34 - (cv.TextHeight + 2) * 2;
  if bal < 0 then price := UIStrFmt('trade_pay', [-bal])
  else if bal > 0 then price := UIStrFmt('trade_receive', [bal])
  else price := UIStr('trade_even');
  cv.DrawText(lx, fy, price, clBlack);
  cv.DrawText(lx, fy + cv.TextHeight + 2,
              UIStrFmt('trade_gold', [FGold, FGold + bal]), clBlack);
end;

procedure TTradePane.OnMouseDown(var e: TUIEvent);
var
  idx: LongInt;
begin
  if e.Pos.Y < FLytTop then exit;
  idx := (e.Pos.Y - FLytTop) div RowH;
  if (idx < 0) or (idx >= FLytMax) then exit;
  if (e.Pos.X >= FLytLX) and (e.Pos.X < FLytLX + FLytColW) then begin
    if idx <= High(FTakeOn) then begin FTakeOn[idx] := not FTakeOn[idx]; e.Handled := True; end;
  end else if (e.Pos.X >= FLytRX) and (e.Pos.X < FLytRX + FLytColW) then begin
    if idx <= High(FGiveOn) then begin FGiveOn[idx] := not FGiveOn[idx]; e.Handled := True; end;
  end;
end;

{ ---- TTradeWindow ---- }

constructor TTradeWindow.Create(AParent: TWidget; l, t: LongInt);
var
  cr: TRect;
begin
  inherited Create(AParent, UIStr('win_trade'), [wfClose, wfDrag], l, t, 400, 452);
  FPane := TTradePane.Create(Content);
  cr := Content.Bounds;
  FPane.SetBounds(0, 0, RectW(cr), RectH(cr));
  FConfirm := TButton.Create(Content, UIStr('trade_confirm'), 8, RectH(cr) - 30, 180, 24);
  FConfirm.OnClick := @OnConfirmClick;
  FDone := TButton.Create(Content, UIStr('trade_done'), RectW(cr) - 108, RectH(cr) - 30, 100, 24);
  FDone.OnClick := @OnDoneClick;
end;

procedure TTradeWindow.SetDeal(const header: String; const stock, pack: array of TTradeItem;
  gold: LongInt);
begin
  FPane.SetDeal(header, stock, pack, gold);
end;

procedure TTradeWindow.CollectGive(out tags: array of LongInt; out n: LongInt);
begin
  FPane.CollectGive(tags, n);
end;

procedure TTradeWindow.CollectTake(out items: array of LongInt; out n: LongInt);
begin
  FPane.CollectTake(items, n);
end;

procedure TTradeWindow.OnConfirmClick(sender: TWidget);
begin
  if Assigned(OnConfirm) then OnConfirm(Self);
end;

procedure TTradeWindow.OnDoneClick(sender: TWidget);
begin
  Visible := False;
end;

{ ---- TMenuPane ---- }

procedure TMenuPane.SetLines(const lines: array of String);
var
  i: LongInt;
begin
  SetLength(FLines, Length(lines));
  for i := 0 to High(lines) do FLines[i] := lines[i];
end;

procedure TMenuPane.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  i, lh, y: LongInt;
begin
  r := AbsRect;
  lh := cv.TextHeight + 6;
  { The block of lines is centered vertically in the pane, each line centered across it. }
  y := r.Top + (RectH(r) - Length(FLines) * lh) div 2;
  for i := 0 to High(FLines) do begin
    cv.DrawText(r.Left + (RectW(r) - cv.TextWidth(FLines[i])) div 2, y, FLines[i],
                clBlack);
    Inc(y, lh);
  end;
end;

{ ---- TMenuWindow ---- }

const
  MENU_MAXBTN = 4;
  MENU_BTNW   = 240;
  MENU_BTNH   = 30;
  MENU_BTNGAP = 12;

constructor TMenuWindow.Create(AParent: TWidget; w, h: LongInt);
var
  d: TDesktop;
  l, t, i: LongInt;
begin
  { Center on the desktop; no close or drag box, so it holds until a choice is made. }
  d := AParent as TDesktop;
  l := (RectW(d.Bounds) - w) div 2;
  t := (RectH(d.Bounds) - h) div 2;
  inherited Create(AParent, UIStr('win_game'), [], l, t, w, h);
  FPane := TMenuPane.Create(Content);
  SetLength(FButtons, MENU_MAXBTN);
  for i := 0 to MENU_MAXBTN - 1 do begin
    FButtons[i] := TButton.Create(Content, '', 0, 0, MENU_BTNW, MENU_BTNH);
    FButtons[i].OnClick := @OnButton;
    FButtons[i].Visible := False;
  end;
end;

procedure TMenuWindow.OnButton(sender: TWidget);
begin
  if Assigned(OnPick) then OnPick((sender as TButton).Tag);
end;

procedure TMenuWindow.SetMenu(const heading: String; const lines: array of String;
  const labels: array of String; const actions: array of LongInt);
var
  bw, th, cw, ch, n, blockH, btnTop, px, i: LongInt;
begin
  Title := heading;
  FPane.SetLines(lines);
  n := Length(labels);
  if n > MENU_MAXBTN then n := MENU_MAXBTN;

  bw := Root.Theme.BorderWidth;
  th := Root.Theme.TitleBarHeight;
  cw := RectW(FBounds) - 2 * bw;
  ch := RectH(FBounds) - th - bw;

  blockH := n * MENU_BTNH + (n - 1) * MENU_BTNGAP;
  btnTop := ch - 20 - blockH;
  px := (cw - MENU_BTNW) div 2;

  { Body lines fill the space above the button block. }
  FPane.SetBounds(8, 8, cw - 8, btnTop - MENU_BTNGAP);

  for i := 0 to MENU_MAXBTN - 1 do
    if i < n then begin
      FButtons[i].Caption := labels[i];
      FButtons[i].Tag := actions[i];
      FButtons[i].SetBounds(px, btnTop + i * (MENU_BTNH + MENU_BTNGAP),
                            px + MENU_BTNW, btnTop + i * (MENU_BTNH + MENU_BTNGAP)
                            + MENU_BTNH);
      FButtons[i].Visible := True;
    end else
      FButtons[i].Visible := False;
end;

end.
