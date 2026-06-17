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
    is tracked in a TCaret. }
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
    procedure ClampCaret;
    function CaretVisualCol: Integer;
    procedure SyncGoalCol;
    procedure MeasureFont;
    procedure RebuildLayout;
    procedure UpdateCaretPos;
    procedure EnsureCaretVisible;
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

function TTextControl.EditableStart: TPoint;
begin
  Result := Point(0, 0);
end;

procedure TTextControl.RefreshView;
begin
  RebuildLayout;
  UpdateCaretPos;
  Invalidate;
end;

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

procedure TTextControl.MoveLeft;
begin
  if FCaret.Col > 0 then
    FCaret.Col := FCaret.Col - 1
  else if FCaret.Line > 0 then
  begin
    // Wrap to the end of the previous logical line.
    FCaret.Line := FCaret.Line - 1;
    FCaret.Col := Length(FContent[FCaret.Line]);
  end;
  ClampCaret;                        // confines to EditableStart for the console
  SyncGoalCol;
end;

procedure TTextControl.MoveRight;
begin
  if FCaret.Col < Length(FContent[FCaret.Line]) then
    FCaret.Col := FCaret.Col + 1
  else if FCaret.Line < FContent.Count - 1 then
  begin
    // Wrap to the start of the next logical line.
    FCaret.Line := FCaret.Line + 1;
    FCaret.Col := 0;
  end;
  ClampCaret;
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
  FCaret.Line := Target.LogicalLine;
  FCaret.Col := Target.StartCol + Min(FGoalCol, Target.Length);
  ClampCaret;                        // note: goal column is intentionally kept
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
  FCaret.Line := Target.LogicalLine;
  FCaret.Col := Target.StartCol + Min(FGoalCol, Target.Length);
  ClampCaret;
end;

procedure TTextControl.MoveHome;
begin
  FCaret.Col := 0;
  ClampCaret;                        // console: raised to the prompt boundary
  SyncGoalCol;
end;

procedure TTextControl.MoveEnd;
begin
  FCaret.Col := Length(FContent[FCaret.Line]);
  ClampCaret;
  SyncGoalCol;
end;

procedure TTextControl.InsertChar(ACh: Char);
var
  Line: string;
begin
  ClampCaret;

  Line := FContent[FCaret.Line];
  System.Insert(ACh, Line, FCaret.Col + 1);
  FContent[FCaret.Line] := Line;
  FCaret.Col := FCaret.Col + 1;
end;

procedure TTextControl.NewLine;
var
  Line, Left, Right: string;
begin
  ClampCaret;

  Line := FContent[FCaret.Line];
  Left := Copy(Line, 1, FCaret.Col);
  Right := Copy(Line, FCaret.Col + 1, MaxInt);

  FContent[FCaret.Line] := Left;
  FContent.Insert(FCaret.Line + 1, Right);

  FCaret.Line := FCaret.Line + 1;
  FCaret.Col := 0;
end;

procedure TTextControl.DeleteBack;
var
  Line: string;
  PrevLen: Integer;
  ES: TPoint;
begin
  ClampCaret;

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
    FCaret.Col := FCaret.Col - 1;
  end
  else if FCaret.Line > 0 then
  begin
    // At start of a line: merge it with the previous line.
    PrevLen := Length(FContent[FCaret.Line - 1]);
    FContent[FCaret.Line - 1] := FContent[FCaret.Line - 1] + FContent[FCaret.Line];
    FContent.Delete(FCaret.Line);
    FCaret.Line := FCaret.Line - 1;
    FCaret.Col := PrevLen;
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

  RebuildLayout;                     // content changed -> re-wrap
  SyncGoalCol;                       // typing resets the preferred column
  UpdateCaretPos;
  EnsureCaretVisible;
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
  UpdateCaretPos;
  EnsureCaretVisible;
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
end;

procedure TTextControl.UpdateCaretPos;
var
  Vr: Integer;
  Row: TVisualRow;
begin
  if (FLayout = nil) or (FCaret = nil) then
    Exit;

  if FContent.Count = 0 then
  begin
    FCaret.MoveTo(0, 0);
    Exit;
  end;

  ClampCaret;
  Vr := FLayout.VisualRowOf(FCaret.Line, FCaret.Col);
  if Vr < 0 then
  begin
    FCaret.MoveTo(0, 0);
    Exit;
  end;

  Row := FLayout[Vr];
  // Subtract the scroll offset; if the caret's row is scrolled out of view the
  // resulting position is off the client area and Win32 simply clips it.
  FCaret.MoveTo((FCaret.Col - Row.StartCol) * FCharWidth,
    Vr * FLineHeight - ScrollOffsetY);
end;

procedure TTextControl.EnsureCaretVisible;
var
  Vr, CaretTop: Integer;
begin
  if (FLayout = nil) or (FLineHeight <= 0) or (FContent.Count = 0) then
    Exit;

  ClampCaret;
  Vr := FLayout.VisualRowOf(FCaret.Line, FCaret.Col);
  if Vr < 0 then
    Exit;

  CaretTop := Vr * FLineHeight;
  ScrollIntoView(CaretTop, CaretTop + FLineHeight);
end;

procedure TTextControl.CaretChanged(Sender: TObject);
begin
  // SetPosition was called. Scroll the new position into view if we already
  // have a real viewport; otherwise defer until the next Resize (the caret can
  // be set during FormCreate, before the handle/size exist).
  if HandleAllocated and (FLineHeight > 0) then
    EnsureCaretVisible
  else
    FCaretFollowPending := True;

  SyncGoalCol;
  UpdateCaretPos;
  Invalidate;
end;

procedure TTextControl.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then
    Exit;
  FWordWrap := AValue;
  RebuildLayout;
  UpdateCaretPos;
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
  UpdateCaretPos;
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

  UpdateCaretPos;
  Invalidate;
end;

procedure TTextControl.Scrolled;
begin
  inherited Scrolled;
  // Keep the caret pinned to its text position as the view scrolls.
  UpdateCaretPos;
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

  // Reposition and restore the caret.
  UpdateCaretPos;
  FCaret.ResumeAfterPaint;
end;

end.
