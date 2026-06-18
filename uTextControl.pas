unit uTextControl;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Math, LCLType,
  uScrollControl, uContent, uCaret, uLayout;

type
  { TTextControl
    Common parent for TCodeEditor and TConsole.
    Paints the content with a monospace font and handles basic text input
    (printable chars, space, backspace, return). Supports soft word wrap via a
    TLayout (the logical text in TContent is never modified). The caret position
    is tracked in a TCaret.

    Caret invariants (A+B+C):
      A. The logical caret is only ever written through SetCaret, which clamps
         it exactly once. (CaretChanged handles the one external write path.)
      B. Readers therefore trust the caret is valid and never re-clamp.
      C. The caret's content-space pixel is cached (FCaretContentX/Y); the
         expensive logical->pixel map (RecalcCaretPixel) runs only when marked
         dirty, while scroll/paint just re-offset it cheaply (PlaceCaret). }
  TTextControl = class(TScrollControl)
  private
    FContent: TContent;
    FCaret: TCaret;
    FLayout: TLayout;
    FWordWrap: Boolean;
    FCharWidth: Integer;     // monospace cell width, px (cached)
    FLineHeight: Integer;    // row height, px (cached)
    FCaretFollowPending: Boolean;  // SetPosition requested before viewport was ready
    FGoalCol: Integer;             // preferred visual column for vertical navigation
    FCaretContentX: Integer;       // caret pixel in content space (cached)
    FCaretContentY: Integer;
    FCaretDirty: Boolean;          // cached content-space pixel is stale
    procedure ClampCaret;
    procedure SetCaret(ALine, ACol: Integer);
    function CaretVisualCol: Integer;
    procedure SyncGoalCol;
    procedure RecalcCaretPixel;
    procedure PlaceCaret;
    procedure RefreshCaret;
    procedure ReconcileCaret;
    procedure EnsureCaretVisible;
    procedure MeasureFont;
    procedure RebuildLayout;
    procedure CaretChanged(Sender: TObject);
    procedure SetWordWrap(AValue: Boolean);
  protected
    procedure PaintContent; override;
    procedure Scrolled; override;
    procedure Resize; override;
    procedure KeyPress(var Key: Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure FontChanged(Sender: TObject); override;
    procedure InitializeWnd; override;

    // Editing primitives - virtual so subclasses (e.g. TConsole) can restrict
    // or repurpose them.
    procedure InsertChar(ACh: Char); virtual;
    procedure NewLine; virtual;
    procedure DeleteBack; virtual;

    // First editable position; everything before it is read-only. Default is
    // (0,0) - the whole document is editable. (X = column, Y = line.)
    function EditableStart: TPoint; virtual;

    // Re-wrap, reposition the caret and repaint after content changes.
    procedure RefreshView;

    // Caret navigation - virtual so subclasses (e.g. TConsole) can restrict or
    // repurpose individual directions. Up/Down move by visual row.
    procedure MoveLeft; virtual;
    procedure MoveRight; virtual;
    procedure MoveUp; virtual;
    procedure MoveDown; virtual;
    procedure MoveHome; virtual;
    procedure MoveEnd; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    property Content: TContent read FContent;
    property Caret: TCaret read FCaret;
    property WordWrap: Boolean read FWordWrap write SetWordWrap;
  end;

implementation

constructor TTextControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FContent := TContent.Create;
  FLayout := TLayout.Create(FContent);
  FCaret := TCaret.Create;
  FCaret.OnChange := CaretChanged;   // SetPosition must keep the caret in view
  FWordWrap := True;
  FCaretDirty := True;

  // Only monospace fonts are supported.
  Font.BeginUpdate;
  Font.Name := 'Courier New';
  Font.Size := 10;
  Font.EndUpdate;

  Color := clWhite;
  TabStop := True;          // allow the control to receive keyboard focus
end;

destructor TTextControl.Destroy;
begin
  FCaret.Free;
  FLayout.Free;
  FContent.Free;
  inherited Destroy;
end;

{ ---- caret invariant (A): the one place the caret is written + clamped ---- }

procedure TTextControl.ClampCaret;
var
  LineLen: Integer;
  ES: TPoint;
begin
  if FCaret.Line < 0 then
    FCaret.Line := 0
  else if FCaret.Line > FContent.Count - 1 then
    FCaret.Line := FContent.Count - 1;

  if FCaret.Col < 0 then
    FCaret.Col := 0
  else begin
    LineLen := Length(FContent[FCaret.Line]);
    if FCaret.Col > LineLen then
       FCaret.Col := LineLen;
  end;

  // Don't let the caret enter the read-only region (no-op for the editor,
  // where EditableStart is (0,0)).
  ES := EditableStart;
  if (FCaret.Line < ES.Y) or ((FCaret.Line = ES.Y) and (FCaret.Col < ES.X)) then
  begin
    FCaret.Line := ES.Y;
    FCaret.Col := ES.X;
  end;
end;

procedure TTextControl.SetCaret(ALine, ACol: Integer);
begin
  FCaret.Line := ALine;
  FCaret.Col := ACol;
  ClampCaret;             // the single validation point (A)
  FCaretDirty := True;    // logical position changed -> pixel needs recompute (C)
end;

function TTextControl.EditableStart: TPoint;
begin
  Result := Point(0, 0);
end;

{ ---- caret pixel cache (C): expensive map runs only when dirty ---- }

procedure TTextControl.RecalcCaretPixel;
var
  Vr: Integer;
  Row: TVisualRow;
begin
  // Leave the caret dirty (cached pixel unchanged) if we can't map it yet -
  // e.g. the layout hasn't been rebuilt for just-added content. A later
  // RefreshCaret/ReconcileCaret retries once the layout is current.
  if (FLayout = nil) or (FContent.Count = 0) then
    Exit;

  Vr := FLayout.VisualRowOf(FCaret.Line, FCaret.Col);
  if Vr < 0 then
    Exit;

  Row := FLayout[Vr];
  FCaretContentX := (FCaret.Col - Row.StartCol) * FCharWidth;
  FCaretContentY := Vr * FLineHeight;
  FCaretDirty := False;              // cleared only on a successful map
end;

procedure TTextControl.PlaceCaret;
begin
  // Cheap: content-space pixel -> screen, just subtract the scroll offset.
  // (If the caret's row is scrolled off-screen, Win32 clips it.)
  FCaret.MoveTo(FCaretContentX, FCaretContentY - ScrollOffsetY);
end;

procedure TTextControl.RefreshCaret;
begin
  // Recompute the content-space pixel only if stale, then place on screen.
  if FCaretDirty then
    RecalcCaretPixel;
  PlaceCaret;
end;

procedure TTextControl.EnsureCaretVisible;
begin
  if (FLayout = nil) or (FLineHeight <= 0) or (FContent.Count = 0) then
    Exit;
  if FCaretDirty then
    RecalcCaretPixel;
  if FCaretDirty then
    Exit;                            // couldn't map the caret yet -> don't scroll
  ScrollIntoView(FCaretContentY, FCaretContentY + FLineHeight);
end;

procedure TTextControl.ReconcileCaret;
begin
  // Single post-action step: bring into view (may scroll) and place.
  EnsureCaretVisible;
  PlaceCaret;
end;

procedure TTextControl.RefreshView;
begin
  // Re-wrap, reposition the caret and repaint after a content change.
  RebuildLayout;
  RefreshCaret;
  Invalidate;
end;

{ ---- goal column for vertical navigation ---- }

function TTextControl.CaretVisualCol: Integer;
var
  Vr: Integer;
  Row: TVisualRow;
begin
  Result := 0;
  if FLayout = nil then
    Exit;
  Vr := FLayout.VisualRowOf(FCaret.Line, FCaret.Col);
  if Vr < 0 then
    Exit;
  Row := FLayout[Vr];
  Result := FCaret.Col - Row.StartCol;   // column offset within the visual row
end;

procedure TTextControl.SyncGoalCol;
begin
  // Record the current visual column as the target for the next vertical move.
  FGoalCol := CaretVisualCol;
end;

{ ---- navigation (B): writes via SetCaret, no defensive clamping ---- }

procedure TTextControl.MoveLeft;
begin
  if FCaret.Col > 0 then
    SetCaret(FCaret.Line, FCaret.Col - 1)
  else if FCaret.Line > 0 then
    // Wrap to the end of the previous logical line.
    SetCaret(FCaret.Line - 1, Length(FContent[FCaret.Line - 1]));
  SyncGoalCol;
end;

procedure TTextControl.MoveRight;
begin
  if FCaret.Col < Length(FContent[FCaret.Line]) then
    SetCaret(FCaret.Line, FCaret.Col + 1)
  else if FCaret.Line < FContent.Count - 1 then
    // Wrap to the start of the next logical line.
    SetCaret(FCaret.Line + 1, 0);
  SyncGoalCol;
end;

procedure TTextControl.MoveUp;
var
  Vr: Integer;
  Target: TVisualRow;
begin
  if FLayout = nil then
    Exit;
  Vr := FLayout.VisualRowOf(FCaret.Line, FCaret.Col);
  if Vr <= 0 then
    Exit;                            // already on the top visual row

  // Land on the same preferred column in the visual row above.
  Target := FLayout[Vr - 1];
  SetCaret(Target.LogicalLine, Target.StartCol + Min(FGoalCol, Target.Length));
  // Note: the goal column is intentionally NOT resynced here.
end;

procedure TTextControl.MoveDown;
var
  Vr: Integer;
  Target: TVisualRow;
begin
  if FLayout = nil then
    Exit;
  Vr := FLayout.VisualRowOf(FCaret.Line, FCaret.Col);
  if (Vr < 0) or (Vr >= FLayout.Count - 1) then
    Exit;                            // already on the bottom visual row

  Target := FLayout[Vr + 1];
  SetCaret(Target.LogicalLine, Target.StartCol + Min(FGoalCol, Target.Length));
end;

procedure TTextControl.MoveHome;
begin
  SetCaret(FCaret.Line, 0);          // console: clamped up to the prompt boundary
  SyncGoalCol;
end;

procedure TTextControl.MoveEnd;
begin
  SetCaret(FCaret.Line, Length(FContent[FCaret.Line]));
  SyncGoalCol;
end;

{ ---- editing (B): writes via SetCaret ---- }

procedure TTextControl.InsertChar(ACh: Char);
var
  Line: string;
begin
  Line := FContent[FCaret.Line];
  System.Insert(ACh, Line, FCaret.Col + 1);
  FContent[FCaret.Line] := Line;
  SetCaret(FCaret.Line, FCaret.Col + 1);
end;

procedure TTextControl.NewLine;
var
  Line, Left, Right: string;
begin
  Line := FContent[FCaret.Line];
  Left := Copy(Line, 1, FCaret.Col);
  Right := Copy(Line, FCaret.Col + 1, MaxInt);

  FContent[FCaret.Line] := Left;
  FContent.Insert(FCaret.Line + 1, Right);

  SetCaret(FCaret.Line + 1, 0);
end;

procedure TTextControl.DeleteBack;
var
  Line: string;
  PrevLen: Integer;
  ES: TPoint;
begin
  // At or before the editable start there is nothing to delete (and we must not
  // merge across the read-only boundary).
  ES := EditableStart;
  if (FCaret.Line < ES.Y) or
     ((FCaret.Line = ES.Y) and (FCaret.Col <= ES.X)) then
    Exit;

  if FCaret.Col > 0 then
  begin
    // Remove the character immediately left of the caret.
    Line := FContent[FCaret.Line];
    System.Delete(Line, FCaret.Col, 1);
    FContent[FCaret.Line] := Line;
    SetCaret(FCaret.Line, FCaret.Col - 1);
  end
  else if FCaret.Line > 0 then
  begin
    // At start of a line: merge it with the previous line.
    PrevLen := Length(FContent[FCaret.Line - 1]);
    FContent[FCaret.Line - 1] := FContent[FCaret.Line - 1] + FContent[FCaret.Line];
    FContent.Delete(FCaret.Line);
    SetCaret(FCaret.Line - 1, PrevLen);
  end;
end;

procedure TTextControl.KeyPress(var Key: Char);
begin
  inherited KeyPress(Key);

  case Key of
    #8:  DeleteBack;                 // Backspace
    #13: NewLine;                    // Return
    #9:  ;                           // ignore Tab for now
  else
    if Key >= ' ' then               // any printable char incl. space (#32)
      InsertChar(Key);
  end;

  RebuildLayout;                     // content changed -> re-wrap (marks caret dirty)
  SyncGoalCol;                       // typing resets the preferred column
  ReconcileCaret;                    // recompute pixel once, scroll into view, place
  Invalidate;
end;

procedure TTextControl.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);

  case Key of
    VK_LEFT:  MoveLeft;
    VK_RIGHT: MoveRight;
    VK_UP:    MoveUp;
    VK_DOWN:  MoveDown;
    VK_HOME:  MoveHome;
    VK_END:   MoveEnd;
  else
    Exit;                            // not a navigation key; leave Key untouched
  end;

  Key := 0;                          // handled
  ReconcileCaret;                    // recompute pixel once, scroll into view, place
end;

procedure TTextControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
    SetFocus;
end;

procedure TTextControl.MeasureFont;
var
  Bmp: TBitmap;
  C: TCanvas;
begin
  Bmp := nil;
  // The control's own canvas is only usable once the handle exists; before
  // that (e.g. during construction) measure on a throwaway bitmap instead.
  if HandleAllocated then
    C := Canvas
  else
  begin
    Bmp := TBitmap.Create;
    C := Bmp.Canvas;
  end;
  try
    C.Font := Font;
    // Monospace: every cell is the same width.
    FCharWidth := C.TextWidth('W');
    FLineHeight := C.TextHeight('Wg');
  finally
    Bmp.Free;
  end;

  FCaret.SetLineHeight(FLineHeight);
  ScrollStep := FLineHeight;         // wheel scrolls in whole-row steps
  RebuildLayout;                     // wrap width depends on the cell width
end;

procedure TTextControl.RebuildLayout;
var
  Cols: Integer;
begin
  if FCharWidth > 0 then
    Cols := Max(1, ViewportWidth div FCharWidth)
  else
    Cols := 1;

  FLayout.SetParams(FWordWrap, Cols);
  FLayout.Rebuild;

  // Tell the scroll base how tall the content is now.
  ContentHeight := FLayout.Count * FLineHeight;

  // Wrapping changed -> the caret's content-space pixel must be recomputed.
  FCaretDirty := True;
end;

procedure TTextControl.CaretChanged(Sender: TObject);
begin
  // The one external write path (TCaret.SetPosition). Clamp here - this is a
  // write boundary, so it's consistent with invariant A.
  ClampCaret;
  FCaretDirty := True;
  SyncGoalCol;

  // Scroll the new position into view if we already have a real viewport;
  // otherwise defer until the next Resize (the caret can be set during
  // FormCreate, before the handle/size exist).
  if HandleAllocated and (FLineHeight > 0) then
    ReconcileCaret
  else
    FCaretFollowPending := True;

  Invalidate;
end;

procedure TTextControl.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then
    Exit;
  FWordWrap := AValue;
  RebuildLayout;
  RefreshCaret;
  Invalidate;
end;

procedure TTextControl.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  // Recompute metrics only when the font actually changes.
  // (FCaret/FLayout may not exist yet during the base constructor's font setup.)
  if (FCaret <> nil) and (FLayout <> nil) then
    MeasureFont;
end;

procedure TTextControl.DoEnter;
begin
  inherited DoEnter;
  //MeasureFont;            // refresh metrics + apply the font to the canvas
  FCaret.Show(Handle);
  RefreshCaret;
end;

procedure TTextControl.DoExit;
begin
  inherited DoExit;
  FCaret.Hide;
end;

procedure TTextControl.InitializeWnd;
begin
  inherited InitializeWnd;
  // The handle now exists, so the real canvas is usable. Measure once here to
  // apply the monospace font to the canvas and cache the metrics, so the very
  // first paint (before the control is ever focused) is already correct.
  //MeasureFont; I saw no use for this. remove in the future....
end;

procedure TTextControl.Resize;
begin
  inherited Resize;
  // The wrap width and content height depend on the client size.
  RebuildLayout;

  // Apply a caret-follow that was requested before the viewport was ready.
  if FCaretFollowPending then
  begin
    EnsureCaretVisible;
    FCaretFollowPending := False;
  end;

  RefreshCaret;
  Invalidate;
end;

procedure TTextControl.Scrolled;
begin
  inherited Scrolled;
  // Scroll changed: re-offset the caret. Cheap - no logical->pixel recompute
  // (the content-space pixel is unchanged by scrolling).
  RefreshCaret;
end;

procedure TTextControl.PaintContent;
var
  i, First, Last: Integer;
  Row: TVisualRow;
begin
  // Hide the system caret while we draw over the client area.
  FCaret.SuspendForPaint;

  // Clear the background (the base draws the bar over the reserved strip after).
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);

  // Draw only the visual rows within the viewport, offset by the scroll
  // position. The font is on the canvas and the row height is cached.
  Canvas.Brush.Style := bsClear;
  if FLineHeight > 0 then
  begin
    First := ScrollOffsetY div FLineHeight;
    Last := (ScrollOffsetY + ClientHeight) div FLineHeight;
  end
  else
  begin
    First := 0;
    Last := FLayout.Count - 1;
  end;
  if First < 0 then
    First := 0;
  if Last > FLayout.Count - 1 then
    Last := FLayout.Count - 1;

  for i := First to Last do
  begin
    Row := FLayout[i];
    if Row.LogicalLine < FContent.Count then
      Canvas.TextOut(0, i * FLineHeight - ScrollOffsetY,
        Copy(FContent[Row.LogicalLine], Row.StartCol + 1, Row.Length));
  end;

  // Reposition and restore the caret (recomputes pixel only if marked dirty).
  RefreshCaret;
  FCaret.ResumeAfterPaint;
end;

end.
