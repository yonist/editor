unit uAutoComplete;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, StdCtrls, LCLType, Types,
  uTextControl, uHighlighter, uTheme;

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
    procedure SetEditor(AValue: TTextControl);
    procedure ApplyFont;
    procedure ReadTheme;
    procedure MoveSel(ADelta: Integer);
    procedure PositionNearCaret;
    procedure DoUpdate;
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
    ItemHeight := Bmp.Canvas.TextHeight('Wg') + 6;
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
  DoUpdate;                           // explicit request (Ctrl+Space)
end;

procedure TAutoCompleteControl.NotifyChanged;
begin
  if Visible then
    DoUpdate;                         // re-fetch the prefix; hides if nothing matches
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

procedure TAutoCompleteControl.DoUpdate;
var
  Prefix: string;
begin
  if FEditor = nil then
    Exit;
  Prefix := FEditor.WordAtCaret;

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
  H: Integer;
begin
  P := FEditor.CaretClientPos;        // client coords in the editor
  Inc(P.Y, FEditor.LineHeight);       // drop below the caret line
  Q := Parent.ScreenToClient(FEditor.ClientToScreen(P));   // parent = the form

  H := Min(FMaxVisible, Items.Count) * ItemHeight + 4;

  if Q.X + FWidthPx > Parent.ClientWidth then
    Q.X := Parent.ClientWidth - FWidthPx;   // clamp to the form's right edge
  if Q.X < 0 then
    Q.X := 0;

  SetBounds(Q.X, Q.Y, FWidthPx, H);
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
  Hide;                               // hide first, so the edit's NotifyChanged is a no-op
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
