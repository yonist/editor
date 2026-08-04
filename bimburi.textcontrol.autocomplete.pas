unit bimburi.textcontrol.autocomplete;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, StdCtrls, LCLType, Types,
  bimburi.textcontrol.textcontrol, bimburi.textcontrol.highlighter, bimburi.textcontrol.theme;

type
  { The host fills AItems with candidates for APrefix (it does the matching). }
  TACProviderEvent = procedure(Sender: TObject; const APrefix: string;
    AItems: TStrings) of object;

  { TAutoCompleteControl
    A borderless owner-drawn list parented to the form. It never takes keyboard
    focus: the editor forwards keystrokes to it (IAutoComplete), and a mouse
    click just picks an item. On accept it replaces the word in the editor. }
  TAutoCompleteControl = class(TCustomListBox, IAutoComplete)
  private
    FEditor: TTextControl;
    FOnGetProp: TACProviderEvent;
    FMaxVisible: Integer;
    FWidthPx: Integer;
    FBg, FSelBg, FText, FSelText: TColor;
    FMinChars: Integer;        // min word length before an IMPLICIT open
    FAutoOpen: Boolean;        // open while typing, without Ctrl+Space
    // One-shot guard consumed by the next NotifyChanged. Accepting a completion
    // hides the popup and then edits the text (ReplaceWordAtCaret -> AfterEdit
    // -> NotifyChanged); with AutoOpen on, that very edit would immediately
    // re-open the popup, because the word now at the caret is the accepted item
    // itself (certainly >= MinChars). The old "hide first, so NotifyChanged is
    // a no-op" trick only worked while NotifyChanged was gated on Visible -
    // AutoOpen removes that gate, so the accept edit must be swallowed here.
    FSuppressNextAuto: Boolean;
    procedure SetEditor(AValue: TTextControl);
    procedure ApplyFont;
    procedure ReadTheme;
    procedure MoveSel(ADelta: Integer);
    procedure PositionNearCaret;
    procedure DoUpdate(AExplicit: Boolean);
    procedure DoResult;
    procedure DrawItemHandler(Control: TWinControl; AIndex: Integer;
      ARect: TRect; AState: TOwnerDrawState);
  protected
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;

    // IAutoComplete
    function Active: Boolean;
    procedure Trigger;
    function HandleKeyDown(var Key: Word; Shift: TShiftState): Boolean;
    procedure NotifyChanged;
    procedure ThemeChanged;
    procedure Cancel;

    property Editor: TTextControl read FEditor write SetEditor;
    property OnGetProp: TACProviderEvent read FOnGetProp write FOnGetProp;
    // MinChars gates OPENING only (and only implicit opens): once the popup is
    // visible, the existing close rules apply unchanged - it closes on an empty
    // prefix or zero matches, not when the prefix shrinks below MinChars, so
    // backspacing from 3 chars to 2 doesn't slam it shut mid-thought.
    property MinChars: Integer read FMinChars write FMinChars;
    // Open automatically as the user types. Fires from ANY edit that leaves a
    // word of >= MinChars at the caret (typing, but also backspacing into a
    // word, paste, undo) - a uniform rule, chosen over "insertions only",
    // which would need an edit-kind threaded through AfterEdit.
    property AutoOpen: Boolean read FAutoOpen write FAutoOpen;
  end;

implementation

uses
  Math;

constructor TAutoCompleteControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := lbOwnerDrawFixed;
  BorderStyle := bsSingle;
  TabStop := False;                    // never a tab target
  Visible := False;
  FMinChars := 1;
  FMaxVisible := 10;
  FWidthPx := 260;
  ItemHeight := 20;                     // provisional; ApplyFont sizes it to the font
  OnDrawItem := DrawItemHandler;
end;

{ Font and colours are read from the editor once here (and again on
  ThemeChanged), not on every popup. }
procedure TAutoCompleteControl.SetEditor(AValue: TTextControl);
begin
  if FEditor = AValue then
    Exit;
  FEditor := AValue;
  if FEditor <> nil then
  begin
    ApplyFont;
    ReadTheme;
  end;
end;

{ Match the editor's monospace font and size each row to fit it (glyphs get
  clipped when ItemHeight is smaller than the DPI-scaled font height). }
procedure TAutoCompleteControl.ApplyFont;
var
  Bmp: TBitmap;
begin
  if FEditor <> nil then
    Font.Assign(FEditor.Font);
  Bmp := TBitmap.Create;                // measure without needing a handle
  try
    Bmp.Canvas.Font.Assign(Font);
    ItemHeight  := Bmp.Canvas.TextHeight('Wg') + 6;
    FWidthPx  := Bmp.Canvas.TextWidth('x') * 30; // show 30 chars
    //self.Height := ItemHeight * 10;
  finally
    Bmp.Free;
  end;
end;

procedure TAutoCompleteControl.ReadTheme;
var
  Th: TTheme;
begin
  if FEditor = nil then
    Exit;
  Th := FEditor.CurrentTheme;
  FBg := Th.Background;
  FSelBg := Th.SelBack;
  FText := Th.Syntax[tkText];
  FSelText := Th.SelFore;
  Color := FBg;
end;

function TAutoCompleteControl.Active: Boolean;
begin
  Result := Visible;
end;

procedure TAutoCompleteControl.MoveSel(ADelta: Integer);
var
  N: Integer;
begin
  if Items.Count = 0 then
    Exit;
  N := ItemIndex + ADelta;
  if N < 0 then
    N := Items.Count - 1;             // wrap
  if N >= Items.Count then
    N := 0;
  ItemIndex := N;
end;

function TAutoCompleteControl.HandleKeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
begin
  Result := True;
  case Key of
    VK_UP:     MoveSel(-1);
    VK_DOWN:   MoveSel(1);
    VK_RETURN,
    VK_TAB:    DoResult;
    VK_ESCAPE: Cancel;
  else
    Result := False;                  // let the editor handle it (typing re-filters)
  end;
  if Result then
    Key := 0;
end;

procedure TAutoCompleteControl.Trigger;
begin
  DoUpdate(True);                     // explicit request (Ctrl+Space)
end;

procedure TAutoCompleteControl.NotifyChanged;
begin
  // Swallow exactly one change notification after an accept (see the
  // FSuppressNextAuto declaration for why). The accept edit always produces a
  // NotifyChanged, so the flag can never linger.
  if FSuppressNextAuto then
  begin
    FSuppressNextAuto := False;
    Exit;
  end;
  // The editor now notifies on every edit even while we are hidden (so that
  // AutoOpen is possible at all); when neither visible nor auto-opening,
  // there is nothing to do.
  if Visible or FAutoOpen then
    DoUpdate(False);                  // re-fetch the prefix; hides if nothing matches
end;

procedure TAutoCompleteControl.ThemeChanged;
begin
  ApplyFont;                            // theme may travel with a font change
  ReadTheme;
  if Visible then
    Invalidate;
end;

procedure TAutoCompleteControl.Cancel;
begin
  if Visible then
    Hide;
end;

procedure TAutoCompleteControl.DoUpdate(AExplicit: Boolean);
var
  Prefix: string;
begin
  if FEditor = nil then
    Exit;
  Prefix := FEditor.WordAtCaret;

  // Explicit (Ctrl+Space) bypasses every prefix rule, including the empty
  // prefix: "I asked, show me everything". The provider already handles
  // APrefix = '' (returns the full list), and accepting with no word at the
  // caret degenerates to a plain insert in ReplaceWordAtCaret. This also
  // covers the console's "." line: '.' is not a word char, so right after
  // typing it the prefix is empty - yet the dot-command list should show.
  if not AExplicit then
  begin
    if Visible then
    begin
      // Already open: original close rule only (empty prefix = word gone).
      if Prefix = '' then
      begin
        Cancel;
        Exit;
      end;
    end
    else
    begin
      // Implicit OPEN (AutoOpen): only when the editor can accept typing at
      // all. Without this gate, submitting an async console command re-opens
      // the popup over the locked console: Enter's edit path runs AfterEdit,
      // whose NotifyChanged fires while the caret still sits at the end of the
      // just-submitted word - a valid prefix, but input is already locked, and
      // nothing on the async path would ever close the popup again. The same
      // gate covers any other notify reaching a non-editable control (e.g. in
      // ReadOnly mode). Explicit opens need no such check: while locked,
      // AcceptsKey swallows Ctrl+Space before Trigger can be reached.
      if not FEditor.Editable then
        Exit;
      // Gated by MinChars. The '' check also keeps a MinChars of 0 from
      // popping the list on every edit.
      if (Prefix = '') or (Length(Prefix) < FMinChars) then
        Exit;
    end;
  end;

  Items.BeginUpdate;
  try
    Items.Clear;
    if Assigned(FOnGetProp) then
      FOnGetProp(Self, Prefix, Items);
  finally
    Items.EndUpdate;
  end;

  if Items.Count = 0 then
  begin
    Cancel;
    Exit;
  end;

  ItemIndex := 0;
  PositionNearCaret;
  if not Visible then
    Show;
  BringToFront;                       // sit above the editor pane
end;

procedure TAutoCompleteControl.PositionNearCaret;
var
  P, Q: TPoint;
  H, LineTop, Y: Integer;
begin
  P := FEditor.CaretClientPos;        // client coords in the editor
  Inc(P.Y, FEditor.LineHeight);       // drop below the caret line
  Q := Parent.ScreenToClient(FEditor.ClientToScreen(P));   // parent = the form

  H := Min(FMaxVisible, Items.Count) * ItemHeight + 4;

  if Q.X + FWidthPx > Parent.ClientWidth then
    Q.X := Parent.ClientWidth - FWidthPx - 3;   // clamp to the form's right edge (-3 is space from the right edge of the form)
  if Q.X < 0 then
    Q.X := 0;

  // Prefer dropping below the caret line; if that runs past the form's bottom
  // (e.g. a console docked at the bottom), flip up above the caret line instead.
  LineTop := Q.Y - FEditor.LineHeight;      // parent-coord top of the caret line
  if Q.Y + H <= Parent.ClientHeight then
    Y := Q.Y                                // fits below
  else
    Y := LineTop - H;                       // flip above
  if Y < 0 then
    Y := 0;                                 // last resort: popup taller than space

  SetBounds(Q.X, Y, FWidthPx, H);
end;

procedure TAutoCompleteControl.DoResult;
var
  S: string;
begin
  if (ItemIndex < 0) or (ItemIndex >= Items.Count) then
  begin
    Cancel;
    Exit;
  end;
  S := Items[ItemIndex];
  Hide;
  // Hiding alone no longer silences the accept edit's NotifyChanged (AutoOpen
  // reacts while hidden) - arm the one-shot suppressor instead.
  FSuppressNextAuto := True;
  FEditor.ReplaceWordAtCaret(S);
  if FEditor.CanFocus then
    FEditor.SetFocus;                 // a mouse pick must not leave the list focused
end;

procedure TAutoCompleteControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Visible and (Button = mbLeft) then
    DoResult;                         // mouse pick = accept
end;

procedure TAutoCompleteControl.DrawItemHandler(Control: TWinControl;
  AIndex: Integer; ARect: TRect; AState: TOwnerDrawState);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then
    Exit;
  if odSelected in AState then
  begin
    Canvas.Brush.Color := FSelBg;
    Canvas.Font.Color := FSelText;
  end
  else
  begin
    Canvas.Brush.Color := FBg;
    Canvas.Font.Color := FText;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ARect);
  Canvas.Brush.Style := bsClear;
  // Vertically center so descenders sit inside the (selection) fill.
  Canvas.TextOut(ARect.Left + 4,
    ARect.Top + (ARect.Bottom - ARect.Top - Canvas.TextHeight(Items[AIndex])) div 2,
    Items[AIndex]);
  Canvas.Brush.Style := bsSolid;
end;

end.
