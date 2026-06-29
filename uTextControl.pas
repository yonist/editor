unit uTextControl;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Math, LCLType, Clipbrd,
  uScrollControl, uContent, uCaret, uLayout, uSelection, uUndo, uHighlighter,
  uTheme;

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
    FLeftMargin: Integer;    // left inset before column 0, px
    FCaretFollowPending: Boolean;  // SetPosition requested before viewport was ready
    FGoalCol: Integer;             // preferred visual column for vertical navigation
    FCaretContentX: Integer;       // caret pixel in content space (cached)
    FCaretContentY: Integer;
    FCaretDirty: Boolean;          // cached content-space pixel is stale
    FSelection: TSelection;        // mouse text selection (independent of caret)
    FSelecting: Boolean;           // a content drag-select is in progress
    FPendingClick: Boolean;        // mouse down in content, click-vs-drag undecided
    FMouseDownPt: TPoint;          // client px where the gesture began
    FSelAnchorPt: TPoint;          // logical (Col,Line) anchor captured at mouse down
    FUndoMgr: TUndoManager;        // undo/redo stacks
    FHighlighter: THighlighter;    // nil = no syntax highlighting
    FColors: TSyntaxColors;        // token kind -> colour
    FHL: TLineHLArray;             // per-line highlight cache (states + tokens)
    FStatesValid: Integer;         // start-states valid for FHL[0..FStatesValid)
    FScanTokens: TTokenArray;      // scratch buffer for state-only lexing
    FTokFirst, FTokLast: Integer;  // line range currently holding cached tokens
    FSelBack: TColor;              // selection band colour (themed)
    FSelFore: TColor;              // selected text colour (themed)
    FThemeKind: TThemeKind;
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
    procedure SetLeftMargin(AValue: Integer);
    procedure CopySelection;
    function SelectedText: string;
    procedure SelectAll;
    function SelectionIsReadOnly: Boolean;
    function ResolveEditPoint(out AStartLine, AOldCount, ACol: Integer;
      out AHead, ATail: string): Boolean;
    procedure DeleteSelectionEdit;
    procedure ReplaceLines(AFirstLine, AOldCount: Integer;
      const ANew: array of string; ACaretAfter: TPoint);
    function ApplyRecord(const ARec: TUndoRecord): TUndoRecord;
    function CaptureSelection: TUndoSel;
    procedure RestoreSelection(const ASel: TUndoSel);
    function SplitText(const AText: string): TUndoLines;
    // Syntax highlight cache.
    procedure SetHighlighter(AValue: THighlighter);
    procedure HLInvalidate(AFromLine: Integer);
    procedure EnsureStates(AUpTo: Integer);
    procedure EnsureLineTokens(ALine: Integer);
    procedure DrawSpan(ALine, ARowStart, AFrom, ATo, AYp: Integer; AColor: TColor);
    procedure DrawColoredSpan(ALine, ARowStart, AFrom, ATo, AYp: Integer);
    procedure DrawRow(const ARow: TVisualRow; AYp: Integer);
    procedure ApplyTheme(const ATheme: TTheme);
    procedure SetThemeKind(AValue: TThemeKind);
  protected
    // Block content mutation - the single choke point (editing, undo/redo, and
    // the console's programmatic appends all route through here), so it is also
    // where the highlight cache is invalidated. Protected for subclasses.
    procedure SwapLines(AFirstLine, ARemoveCount: Integer;
      const ANew: array of string);
    // Release cached tokens for lines outside [AFirst, ALast]. The console keeps
    // its immutable scrollback by overriding this to a no-op.
    procedure EvictTokens(AFirst, ALast: Integer); virtual;
    procedure PaintContent; override;
    procedure Scrolled; override;
    procedure Resize; override;
    procedure KeyPress(var Key: Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;

    // Mouse caret positioning. LogicalFromPoint is the inverse of
    // RecalcCaretPixel (client pixel -> logical position); PositionCaretFromMouse
    // applies it. Virtual so subclasses (e.g. TConsole) can refuse clicks that
    // fall outside their editable region.
    // SnapToNearest rounds X to the closest character boundary (correct for
    // placing the caret on a click). Pass False to snap down to the character
    // actually under the cursor (correct for a selection anchor: a drag must
    // start from the clicked letter, not its right-hand neighbour).
    function LogicalFromPoint(X, Y: Integer;
      SnapToNearest: Boolean = True): TPoint;
    procedure PositionCaretFromMouse(X, Y: Integer); virtual;

    procedure DoEnter; override;
    procedure DoExit; override;
    procedure FontChanged(Sender: TObject); override;
    procedure InitializeWnd; override;

    // Editing primitives - virtual so subclasses (e.g. TConsole) can restrict
    // or repurpose them.
    procedure InsertChar(ACh: Char); virtual;
    procedure NewLine; virtual;
    procedure DeleteBack; virtual;
    procedure DeleteForward; virtual;

    // Insert (possibly multi-line) text at the caret, replacing any selection,
    // as a single undo step. Protected so subclasses can feed it transformed
    // text (the console strips line breaks before pasting).
    procedure InsertText(const AText: string);
    procedure Cut;
    procedure Paste; virtual;

    // Standard post-edit refresh: re-wrap, reposition + scroll the caret, repaint.
    procedure AfterEdit;

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

    // Drop the selection (repaints if one was showing). Protected so subclasses
    // can clear it - e.g. the console clears it inside its history Up/Down.
    procedure ClearSelection;

    // Clear the undo/redo stacks. The console resets per input line.
    procedure ResetUndo;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Undo;
    procedure Redo;

    // Content serialization (text only). Virtual: TConsole overrides to refuse.
    procedure SaveToStream(AStream: TStream); virtual;
    procedure LoadFromStream(AStream: TStream); virtual;

    property Content: TContent read FContent;
    property Caret: TCaret read FCaret;
    property WordWrap: Boolean read FWordWrap write SetWordWrap;
    property LeftMargin: Integer read FLeftMargin write SetLeftMargin;
    property Highlighter: THighlighter read FHighlighter write SetHighlighter;
    property Colors: TSyntaxColors read FColors write FColors;
    property ThemeKind: TThemeKind read FThemeKind write SetThemeKind;
  end;

implementation

const
  SelectThreshold = 3;   // px the mouse must move before a click becomes a drag

constructor TTextControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FContent := TContent.Create;
  FLayout := TLayout.Create(FContent);
  FCaret := TCaret.Create;
  FCaret.OnChange := CaretChanged;   // SetPosition must keep the caret in view
  FSelection := TSelection.Create;
  FUndoMgr := TUndoManager.Create;
  FWordWrap := True;
  FLeftMargin := 4;
  FCaretDirty := True;
  FStatesValid := 0;
  FTokFirst := 0;
  FTokLast := -1;                   // empty token-cached range

  // Only monospace fonts are supported.
  Font.BeginUpdate;
  Font.Name := 'Courier New';
  Font.Size := 18;
  Font.EndUpdate;

  TabStop := True;          // allow the control to receive keyboard focus
  FThemeKind := thDark;
  ApplyTheme(DarkTheme);    // default theme (sets Color, syntax, selection, caret, bar)
end;

destructor TTextControl.Destroy;
begin
  FUndoMgr.Free;
  FSelection.Free;
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
  FCaretContentX := FLeftMargin + (FCaret.Col - Row.StartCol) * FCharWidth;
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

{ ---- selection + clipboard ---- }

procedure TTextControl.ClearSelection;
begin
  // It's safe because Invalidate is asynchronous — it doesn't paint, it just flags the control dirty so Windows posts a WM_PAINT later.
  // By the time PaintContent actually runs, FSelection.Clear has already
  if not FSelection.IsEmpty then begin
    Invalidate;          // a highlight was showing -> repaint to erase it
    FSelection.Clear;
  end;
end;

function TTextControl.SelectedText: string;
var
  SLine, SCol, ELine, ECol, i: Integer;
begin
  Result := '';
  if FSelection.IsEmpty then
    Exit;
  FSelection.GetRange(SLine, SCol, ELine, ECol);

  if SLine = ELine then
  begin
    Result := Copy(FContent[SLine], SCol + 1, ECol - SCol);
    Exit;
  end;

  // First line from SCol to its end, whole interior lines, last line up to ECol.
  Result := Copy(FContent[SLine], SCol + 1, MaxInt);
  for i := SLine + 1 to ELine - 1 do
    Result := Result + LineEnding + FContent[i];
  Result := Result + LineEnding + Copy(FContent[ELine], 1, ECol);
end;

procedure TTextControl.CopySelection;
begin
  if FSelection.IsEmpty then
    Exit;
  Clipboard.AsText := SelectedText;
  ClearSelection;        // copy consumes the selection (and repaints)
end;

procedure TTextControl.SelectAll;
var
  ES: TPoint;
  LastIdx: Integer;
begin
  if FContent.Count = 0 then
    Exit;

  // Anchor at the first editable position, extend to the end of the last line.
  // For the console EditableStart is the prompt boundary, so this naturally
  // selects only the input line (and selects nothing when input is inactive).
  ES := EditableStart;
  LastIdx := FContent.Count - 1;
  FSelection.SetAnchor(ES.Y, ES.X);
  FSelection.ExtendTo(LastIdx, Length(FContent[LastIdx]));
  Invalidate;            // show the highlight (the caret is left where it is)
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

function TTextControl.SelectionIsReadOnly: Boolean;
var
  SLine, SCol, ELine, ECol: Integer;
  ES: TPoint;
begin
  Result := False;
  if FSelection.IsEmpty then
    Exit;
  FSelection.GetRange(SLine, SCol, ELine, ECol);
  ES := EditableStart;
  // The selection begins before the editable region (e.g. console scrollback).
  Result := (SLine < ES.Y) or ((SLine = ES.Y) and (SCol < ES.X));
end;

{ ---- undo/redo: the line-block funnel (every edit goes through ReplaceLines) ---- }

procedure TTextControl.SwapLines(AFirstLine, ARemoveCount: Integer;
  const ANew: array of string);
var
  i: Integer;
begin
  // Mechanical block replace; no recording. Shared by editing and undo/redo.
  for i := 1 to ARemoveCount do
    FContent.Delete(AFirstLine);
  for i := 0 to High(ANew) do
    FContent.Insert(AFirstLine + i, ANew[i]);
  HLInvalidate(AFirstLine);          // content from here changed -> re-lex
end;

{ ---- syntax highlighting: state + token cache ---- }

procedure TTextControl.SetHighlighter(AValue: THighlighter);
begin
  if FHighlighter = AValue then
    Exit;
  FHighlighter := AValue;
  // Everything must be re-lexed.
  SetLength(FHL, 0);
  FStatesValid := 0;
  FTokFirst := 0;
  FTokLast := -1;
  Invalidate;
end;

procedure TTextControl.HLInvalidate(AFromLine: Integer);
begin
  if AFromLine < 0 then
    AFromLine := 0;
  // Start-states and tokens from AFromLine are suspect; drop them. Lines above
  // are unchanged, so their cache stays valid. EnsureStates rebuilds lazily.
  if AFromLine < FStatesValid then
    FStatesValid := AFromLine;
  if AFromLine < Length(FHL) then
    SetLength(FHL, AFromLine);       // releases token arrays at/after AFromLine
  if FTokLast >= AFromLine then
    FTokLast := AFromLine - 1;
end;

procedure TTextControl.EnsureStates(AUpTo: Integer);
var
  Cnt: Integer;
  S: TLexState;
begin
  if FHighlighter = nil then
    Exit;
  if AUpTo > FContent.Count - 1 then
    AUpTo := FContent.Count - 1;
  if AUpTo < 0 then
    Exit;

  if Length(FHL) < FContent.Count then
    SetLength(FHL, FContent.Count);  // grow to match content (preserves [0, old))

  if FStatesValid = 0 then
  begin
    FHL[0].State := 0;               // the first line is always in the normal state
    FStatesValid := 1;
  end;

  // Propagate start-states forward by lexing each predecessor (tokens discarded).
  while FStatesValid <= AUpTo do
  begin
    S := FHL[FStatesValid - 1].State;
    FHighlighter.ScanLine(FContent[FStatesValid - 1], S, FScanTokens, Cnt);
    FHL[FStatesValid].State := S;
    Inc(FStatesValid);
  end;
end;

procedure TTextControl.EnsureLineTokens(ALine: Integer);
var
  S: TLexState;
begin
  EnsureStates(ALine);               // FHL[ALine].State now valid
  if FHL[ALine].HasTokens then
    Exit;
  S := FHL[ALine].State;
  FHighlighter.ScanLine(FContent[ALine], S, FHL[ALine].Tokens, FHL[ALine].Count);
  FHL[ALine].HasTokens := True;
  // Token-lexing also produced this line's end-state: advance the frontier so
  // the next line isn't lexed twice.
  if (FStatesValid = ALine + 1) and (ALine + 1 < Length(FHL)) then
  begin
    FHL[ALine + 1].State := S;
    FStatesValid := ALine + 2;
  end;
end;

procedure TTextControl.DrawSpan(ALine, ARowStart, AFrom, ATo, AYp: Integer;
  AColor: TColor);
begin
  if ATo <= AFrom then
    Exit;
  Canvas.Font.Color := AColor;
  Canvas.TextOut(FLeftMargin + (AFrom - ARowStart) * FCharWidth, AYp,
    Copy(FContent[ALine], AFrom + 1, ATo - AFrom));
end;

procedure TTextControl.DrawColoredSpan(ALine, ARowStart, AFrom, ATo,
  AYp: Integer);
var
  ti, col, ts, te: Integer;
  T: TToken;
begin
  col := AFrom;
  for ti := 0 to FHL[ALine].Count - 1 do
  begin
    T := FHL[ALine].Tokens[ti];
    if T.StartCol >= ATo then
      Break;
    if T.StartCol + T.Length <= AFrom then
      Continue;
    ts := T.StartCol;
    if ts < AFrom then ts := AFrom;
    te := T.StartCol + T.Length;
    if te > ATo then te := ATo;
    if ts > col then
      DrawSpan(ALine, ARowStart, col, ts, AYp, FColors[tkText]);  // gap = plain
    DrawSpan(ALine, ARowStart, ts, te, AYp, FColors[T.Kind]);
    col := te;
  end;
  if col < ATo then
    DrawSpan(ALine, ARowStart, col, ATo, AYp, FColors[tkText]);
end;

procedure TTextControl.DrawRow(const ARow: TVisualRow; AYp: Integer);
var
  L, RowEnd, C0, C1, LineLen: Integer;
  HasSel: Boolean;
begin
  L := ARow.LogicalLine;
  LineLen := Length(FContent[L]);
  RowEnd := ARow.StartCol + ARow.Length;

  HasSel := (not FSelection.IsEmpty) and
            FSelection.RangeOnLine(L, LineLen, C0, C1);
  if HasSel then
  begin
    if C0 < ARow.StartCol then C0 := ARow.StartCol;
    if C1 > RowEnd then C1 := RowEnd;
    if C1 <= C0 then HasSel := False;
  end;

  if FHighlighter <> nil then
    EnsureLineTokens(L);

  if not HasSel then
  begin
    if FHighlighter <> nil then
      DrawColoredSpan(L, ARow.StartCol, ARow.StartCol, RowEnd, AYp)
    else
      DrawSpan(L, ARow.StartCol, ARow.StartCol, RowEnd, AYp, FColors[tkText]);
    Exit;
  end;

  // Fill the selection band, then draw: token-coloured outside, one uniform
  // selection foreground inside.
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FSelBack;
  Canvas.FillRect(Rect(FLeftMargin + (C0 - ARow.StartCol) * FCharWidth, AYp,
                       FLeftMargin + (C1 - ARow.StartCol) * FCharWidth, AYp + FLineHeight));
  Canvas.Brush.Style := bsClear;

  if FHighlighter <> nil then
  begin
    DrawColoredSpan(L, ARow.StartCol, ARow.StartCol, C0, AYp);
    DrawColoredSpan(L, ARow.StartCol, C1, RowEnd, AYp);
  end
  else
  begin
    DrawSpan(L, ARow.StartCol, ARow.StartCol, C0, AYp, FColors[tkText]);
    DrawSpan(L, ARow.StartCol, C1, RowEnd, AYp, FColors[tkText]);
  end;
  DrawSpan(L, ARow.StartCol, C0, C1, AYp, FSelFore);   // selected text
end;

procedure TTextControl.ApplyTheme(const ATheme: TTheme);
begin
  Color := ATheme.Background;
  FSelBack := ATheme.SelBack;
  FSelFore := ATheme.SelFore;
  FColors := ATheme.Syntax;
  FCaret.SetColors(ATheme.Caret, ATheme.Background);   // XOR-drawn against the bg
  SetScrollColors(ATheme.ScrollTrack, ATheme.ScrollThumb);   // inherited
  Invalidate;
end;

procedure TTextControl.SetThemeKind(AValue: TThemeKind);
begin
  FThemeKind := AValue;
  case AValue of
    thLight: ApplyTheme(LightTheme);
    thDark:  ApplyTheme(DarkTheme);
  end;
end;

procedure TTextControl.EvictTokens(AFirst, ALast: Integer);
var
  k: Integer;
begin
  // Free token arrays for lines painted last time that are now off-screen. Only
  // the previous window is scanned, so this is viewport-bounded.
  for k := FTokFirst to FTokLast do
    if ((k < AFirst) or (k > ALast)) and (k < Length(FHL)) then
    begin
      SetLength(FHL[k].Tokens, 0);
      FHL[k].Count := 0;
      FHL[k].HasTokens := False;
    end;
  FTokFirst := AFirst;
  FTokLast := ALast;
end;

function TTextControl.CaptureSelection: TUndoSel;
var
  SLine, SCol, ELine, ECol: Integer;
begin
  Result.SelStart := Point(0, 0);
  Result.SelEnd := Point(0, 0);
  Result.HasSel := not FSelection.IsEmpty;
  if Result.HasSel then
  begin
    FSelection.GetRange(SLine, SCol, ELine, ECol);
    Result.SelStart := Point(SCol, SLine);
    Result.SelEnd := Point(ECol, ELine);
  end;
end;

procedure TTextControl.RestoreSelection(const ASel: TUndoSel);
begin
  if ASel.HasSel then
  begin
    FSelection.SetAnchor(ASel.SelStart.Y, ASel.SelStart.X);
    FSelection.ExtendTo(ASel.SelEnd.Y, ASel.SelEnd.X);
  end
  else
    ClearSelection;
end;

procedure TTextControl.ReplaceLines(AFirstLine, AOldCount: Integer;
  const ANew: array of string; ACaretAfter: TPoint);
var
  Rec: TUndoRecord;
  i: Integer;
begin
  // Record the affected block as it is now (lazy: NewLines is read back at undo).
  Rec.FirstLine := AFirstLine;
  SetLength(Rec.Lines, AOldCount);
  for i := 0 to AOldCount - 1 do
    Rec.Lines[i] := FContent[AFirstLine + i];
  Rec.OtherCount := Length(ANew);
  Rec.CaretTarget := Point(FCaret.Col, FCaret.Line);   // caret before the edit
  Rec.CaretOther := ACaretAfter;
  Rec.SelTarget := CaptureSelection;   // pre-edit selection -> restored on undo
  Rec.SelOther.HasSel := False;        // redo direction is caret-only
  Rec.SelOther.SelStart := Point(0, 0);
  Rec.SelOther.SelEnd := Point(0, 0);
  FUndoMgr.RecordEdit(Rec);

  ClearSelection;              // the edit consumes any selection
  SwapLines(AFirstLine, AOldCount, ANew);
  SetCaret(ACaretAfter.Y, ACaretAfter.X);
end;

function TTextControl.ApplyRecord(const ARec: TUndoRecord): TUndoRecord;
var
  i: Integer;
begin
  // Capture the block we are about to overwrite -> it becomes the inverse (with
  // the caret/selection pairs swapped), then swap in this record's block and
  // restore its caret and selection.
  Result.FirstLine := ARec.FirstLine;
  SetLength(Result.Lines, ARec.OtherCount);
  for i := 0 to ARec.OtherCount - 1 do
    Result.Lines[i] := FContent[ARec.FirstLine + i];
  Result.OtherCount := Length(ARec.Lines);
  Result.CaretTarget := ARec.CaretOther;
  Result.CaretOther := ARec.CaretTarget;
  Result.SelTarget := ARec.SelOther;
  Result.SelOther := ARec.SelTarget;

  SwapLines(ARec.FirstLine, ARec.OtherCount, ARec.Lines);
  SetCaret(ARec.CaretTarget.Y, ARec.CaretTarget.X);
  RestoreSelection(ARec.SelTarget);
end;

procedure TTextControl.Undo;
var
  Rec: TUndoRecord;
begin
  if not FUndoMgr.PeekUndo(Rec) then
    Exit;
  // ApplyRecord restores content, caret AND selection, and returns the inverse
  // (redo form), which we commit back into the same slot.
  FUndoMgr.CommitUndo(ApplyRecord(Rec));
  AfterEdit;
end;

procedure TTextControl.Redo;
var
  Rec: TUndoRecord;
begin
  if not FUndoMgr.PeekRedo(Rec) then
    Exit;
  FUndoMgr.CommitRedo(ApplyRecord(Rec));
  AfterEdit;
end;

procedure TTextControl.ResetUndo;
begin
  FUndoMgr.Clear;
end;

procedure TTextControl.SaveToStream(AStream: TStream);
begin
  FContent.SaveToStream(AStream);   // text only; no caret/scroll/selection
end;

procedure TTextControl.LoadFromStream(AStream: TStream);
begin
  FContent.LoadFromStream(AStream);

  // Fresh document: this is a wholesale replacement, not an undoable edit, so it
  // bypasses the SwapLines funnel and resets the derived state by hand.
  FUndoMgr.Clear;
  ClearSelection;
  HLInvalidate(0);                  // drop the whole highlight cache
  SetCaret(0, 0);                   // caret at the top of the document
  RebuildLayout;
  SyncGoalCol;
  ReconcileCaret;                   // recompute pixel + scroll the top into view
  Invalidate;
end;

{ ---- selection resolution for the editing primitives ---- }

function TTextControl.ResolveEditPoint(out AStartLine, AOldCount, ACol: Integer;
  out AHead, ATail: string): Boolean;
var
  SLine, SCol, ELine, ECol: Integer;
begin
  Result := True;
  if FSelection.IsEmpty then
  begin
    // No selection: edit at the caret on its line.
    AStartLine := FCaret.Line;
    AOldCount := 1;
    AHead := Copy(FContent[AStartLine], 1, FCaret.Col);
    ATail := Copy(FContent[AStartLine], FCaret.Col + 1, MaxInt);
    ACol := FCaret.Col;
  end
  else if SelectionIsReadOnly then
  begin
    ClearSelection;
    Result := False;             // read-only selection -> caller aborts
  end
  else
  begin
    // Editable selection: the edit replaces the whole span in one record.
    // ReplaceLines snapshots and clears the selection.
    FSelection.GetRange(SLine, SCol, ELine, ECol);
    AStartLine := SLine;
    AOldCount := ELine - SLine + 1;
    AHead := Copy(FContent[SLine], 1, SCol);
    ATail := Copy(FContent[ELine], ECol + 1, MaxInt);
    ACol := SCol;
  end;
end;

procedure TTextControl.DeleteSelectionEdit;
var
  SLine, SCol, ELine, ECol: Integer;
  Head, Tail: string;
begin
  FSelection.GetRange(SLine, SCol, ELine, ECol);
  Head := Copy(FContent[SLine], 1, SCol);
  Tail := Copy(FContent[ELine], ECol + 1, MaxInt);
  ReplaceLines(SLine, ELine - SLine + 1, [Head + Tail], Point(SCol, SLine));
end;

function TTextControl.SplitText(const AText: string): TUndoLines;
var
  S: string;
  i, Start, N: Integer;
begin
  // Normalize CRLF/CR to LF, then split on LF. A trailing line break yields a
  // trailing empty segment (so a pasted "a\n" inserts "a" + a new empty line).
  S := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  S := StringReplace(S, #13, #10, [rfReplaceAll]);

  N := 1;
  for i := 1 to Length(S) do
    if S[i] = #10 then
      Inc(N);
  SetLength(Result, N);

  N := 0;
  Start := 1;
  for i := 1 to Length(S) do
    if S[i] = #10 then
    begin
      Result[N] := Copy(S, Start, i - Start);
      Inc(N);
      Start := i + 1;
    end;
  Result[N] := Copy(S, Start, Length(S) - Start + 1);
end;

procedure TTextControl.InsertText(const AText: string);
var
  StartLine, OldCount, Col, i, M: Integer;
  Head, Tail: string;
  Segs, NewLines: TUndoLines;
  CaretAfter: TPoint;
begin
  if AText = '' then
    Exit;
  if not ResolveEditPoint(StartLine, OldCount, Col, Head, Tail) then
    Exit;                          // read-only selection -> ignore

  Segs := SplitText(AText);
  M := Length(Segs);

  if M = 1 then
  begin
    // Single line: splice the text between Head and Tail.
    SetLength(NewLines, 1);
    NewLines[0] := Head + Segs[0] + Tail;
    CaretAfter := Point(Length(Head) + Length(Segs[0]), StartLine);
  end
  else
  begin
    // Multi-line: Head joins the first segment, Tail joins the last, the middle
    // segments become their own lines.
    SetLength(NewLines, M);
    NewLines[0] := Head + Segs[0];
    for i := 1 to M - 2 do
      NewLines[i] := Segs[i];
    NewLines[M - 1] := Segs[M - 1] + Tail;
    CaretAfter := Point(Length(Segs[M - 1]), StartLine + M - 1);
  end;

  ReplaceLines(StartLine, OldCount, NewLines, CaretAfter);
end;

procedure TTextControl.Cut;
begin
  if FSelection.IsEmpty then
    Exit;
  Clipboard.AsText := SelectedText;   // copy first (works for read-only too)
  if SelectionIsReadOnly then
    ClearSelection                    // can't delete read-only -> just drop it
  else
    DeleteSelectionEdit;              // records undo + removes the selection
  AfterEdit;
end;

procedure TTextControl.Paste;
begin
  InsertText(Clipboard.AsText);
  AfterEdit;
end;

procedure TTextControl.AfterEdit;
begin
  RebuildLayout;       // content changed -> re-wrap (marks the caret pixel dirty)
  SyncGoalCol;         // a horizontal edit resets the preferred column
  ReconcileCaret;      // recompute the caret pixel once, scroll into view, place
  Invalidate;
end;

procedure TTextControl.InsertChar(ACh: Char);
var
  StartLine, OldCount, Col: Integer;
  Head, Tail: string;
begin
  if not ResolveEditPoint(StartLine, OldCount, Col, Head, Tail) then
    Exit;                            // read-only selection -> ignore key
  ReplaceLines(StartLine, OldCount, [Head + ACh + Tail], Point(Col + 1, StartLine));
end;

procedure TTextControl.NewLine;
var
  StartLine, OldCount, Col: Integer;
  Head, Tail: string;
begin
  if not ResolveEditPoint(StartLine, OldCount, Col, Head, Tail) then
    Exit;
  // Split at the edit point: Head stays on StartLine, Tail moves to a new line.
  ReplaceLines(StartLine, OldCount, [Head, Tail], Point(0, StartLine + 1));
end;

procedure TTextControl.DeleteBack;
var
  Merged: string;
  PrevLen: Integer;
  ES: TPoint;
begin
  // With a selection, Backspace deletes it (or drops a read-only one) - never a
  // neighbouring character.
  if not FSelection.IsEmpty then
  begin
    if SelectionIsReadOnly then ClearSelection
    else DeleteSelectionEdit;
    Exit;
  end;

  // At or before the editable start there is nothing to delete (no cross-boundary
  // merge).
  ES := EditableStart;
  if (FCaret.Line < ES.Y) or
     ((FCaret.Line = ES.Y) and (FCaret.Col <= ES.X)) then
    Exit;

  if FCaret.Col > 0 then
  begin
    // Remove the character immediately left of the caret.
    Merged := FContent[FCaret.Line];
    System.Delete(Merged, FCaret.Col, 1);
    ReplaceLines(FCaret.Line, 1, [Merged], Point(FCaret.Col - 1, FCaret.Line));
  end
  else  // start of line: merge it with the previous line
  begin
    PrevLen := Length(FContent[FCaret.Line - 1]);
    Merged := FContent[FCaret.Line - 1] + FContent[FCaret.Line];
    ReplaceLines(FCaret.Line - 1, 2, [Merged], Point(PrevLen, FCaret.Line - 1));
  end;
end;

procedure TTextControl.DeleteForward;
var
  Merged: string;
begin
  // With a selection, Delete deletes it (or drops a read-only one) - never a
  // neighbouring character.
  if not FSelection.IsEmpty then
  begin
    if SelectionIsReadOnly then ClearSelection
    else DeleteSelectionEdit;
    Exit;
  end;

  if FCaret.Col < Length(FContent[FCaret.Line]) then
  begin
    // Remove the character immediately right of the caret (caret stays put).
    Merged := FContent[FCaret.Line];
    System.Delete(Merged, FCaret.Col + 1, 1);
    ReplaceLines(FCaret.Line, 1, [Merged], Point(FCaret.Col, FCaret.Line));
  end
  else if FCaret.Line < FContent.Count - 1 then
  begin
    // At end of line: pull the next line up onto this one.
    Merged := FContent[FCaret.Line] + FContent[FCaret.Line + 1];
    ReplaceLines(FCaret.Line, 2, [Merged], Point(FCaret.Col, FCaret.Line));
  end;
end;

procedure TTextControl.KeyPress(var Key: Char);
begin
  inherited KeyPress(Key);

  // Text input only. Editing commands (Backspace, Enter, Delete) and navigation
  // are handled in KeyDown; any control character that still reaches here is
  // ignored. InsertChar consumes the selection, so no explicit clear is needed.
  if Key < ' ' then
    Exit;

  InsertChar(Key);                   // any printable char incl. space (#32)
  AfterEdit;
end;

procedure TTextControl.KeyDown(var Key: Word; Shift: TShiftState);
var
  Selecting, IsNav, IsEditKey, IsCtrlCmd: Boolean;
  SLine, SCol, ELine, ECol: Integer;
begin
  inherited KeyDown(Key, Shift);

  // Ctrl shortcuts. Each handler repaints itself (Cut/Paste/Undo/Redo via
  // AfterEdit; Copy/SelectAll repaint as they change the selection), so this is
  // a pure dispatch with a single consume. An unhandled Ctrl combo falls
  // through to the navigation handling below.
  if ssCtrl in Shift then
  begin
    IsCtrlCmd := True;
    case Key of
      Ord('C'): CopySelection;
      Ord('A'): SelectAll;
      Ord('X'): Cut;
      Ord('V'): Paste;
      Ord('Z'): if ssShift in Shift then Redo else Undo;
      Ord('Y'): Redo;
    else
      IsCtrlCmd := False;
    end;

    if IsCtrlCmd then
    begin
      Key := 0;                      // handled (also suppresses the KeyPress)
      Exit;
    end;
  end;

  // Editing commands all live here so they're in one place. Backspace and Enter
  // also arrive as control characters in KeyPress, but setting Key := 0
  // suppresses that follow-up - and KeyPress ignores control characters anyway,
  // so a widgetset that still delivers it does no harm.
  IsEditKey := true;
  case Key of
    VK_BACK:   DeleteBack;
    VK_DELETE: DeleteForward;
    VK_RETURN: NewLine;
    else begin
      IsEditKey:= false;
    end;
  end;

  if IsEditKey then begin
    Key := 0;
    AfterEdit;
    Exit;
  end;

  IsNav := (Key = VK_LEFT) or (Key = VK_RIGHT) or (Key = VK_UP) or
           (Key = VK_DOWN) or (Key = VK_HOME) or (Key = VK_END);
  if not IsNav then
    Exit;                            // not a navigation key; leave Key untouched

  Selecting := ssShift in Shift;

  // Plain Left/Right with a live selection collapses the caret onto the
  // selection boundary (standard editor feel) instead of moving one character.
  if (not Selecting) and (not FSelection.IsEmpty) and
     ((Key = VK_LEFT) or (Key = VK_RIGHT)) then
  begin
    FSelection.GetRange(SLine, SCol, ELine, ECol);
    if Key = VK_LEFT then
      SetCaret(SLine, SCol)
    else
      SetCaret(ELine, ECol);
    ClearSelection;
    SyncGoalCol;
    Key := 0;
    ReconcileCaret;
    Exit;
  end;

  // Anchor the selection at the (pre-move) caret on the first Shift+navigation
  // keystroke. Subclasses whose move is not caret navigation (the console maps
  // Up/Down to history) clear the selection inside the Move call below, which
  // makes the ExtendTo afterwards a harmless no-op - no special-casing here.
  if Selecting and FSelection.IsEmpty then
    FSelection.SetAnchor(FCaret.Line, FCaret.Col);

  case Key of
    VK_LEFT:  MoveLeft;
    VK_RIGHT: MoveRight;
    VK_UP:    MoveUp;
    VK_DOWN:  MoveDown;
    VK_HOME:  MoveHome;
    VK_END:   MoveEnd;
  end;
  Key := 0;                          // handled

  if Selecting then
  begin
    FSelection.ExtendTo(FCaret.Line, FCaret.Col);  // active end follows the caret
    Invalidate;                      // the selection band may have changed
  end
  else
    ClearSelection;                  // plain navigation collapses any selection

  ReconcileCaret;                    // recompute pixel once, scroll into view, place
end;

procedure TTextControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);   // base may start a scrollbar drag
  if CanFocus then
    SetFocus;

  // Begin a gesture in the content area (not on the reserved scrollbar strip).
  // We can't yet tell a click from a drag, so defer the caret move to MouseUp
  // (a drag selects and must NOT move the caret - invariant of this feature).
  if (Button = mbLeft) and (X < ClientWidth - BarWidth) then
  begin
    FMouseDownPt := Point(X, Y);
    // Anchor on the letter under the cursor (floor), so a drag selects starting
    // from the clicked character rather than rounding to its neighbour.
    FSelAnchorPt := LogicalFromPoint(X, Y, False);   // logical (Col,Line) anchor
    FPendingClick := True;
    FSelecting := False;
    ClearSelection;                  // starting a new gesture drops the old one
  end;
end;

procedure TTextControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  inherited MouseMove(Shift, X, Y);  // base handles the scrollbar thumb drag

  if (not (ssLeft in Shift)) or (not (FPendingClick or FSelecting)) then
    Exit;

  // Promote a pending click to a drag-select once it passes the threshold.
  if FPendingClick and
     (Abs(X - FMouseDownPt.X) + Abs(Y - FMouseDownPt.Y) >= SelectThreshold) then
  begin
    FPendingClick := False;
    FSelecting := True;
    FSelection.SetAnchor(FSelAnchorPt.Y, FSelAnchorPt.X);
  end;

  if FSelecting then
  begin
    P := LogicalFromPoint(X, Y);
    FSelection.ExtendTo(P.Y, P.X);
    Invalidate;                      // redraw the highlight; caret untouched
  end;
end;

procedure TTextControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;

  if FSelecting then
  begin
    FSelecting := False;
    // A drag that collapsed back to a point is treated as a plain click.
    if FSelection.IsEmpty then
    begin
      FSelection.Clear;
      PositionCaretFromMouse(X, Y);
    end;
    // Otherwise keep the selection (already painted); the caret stays put.
  end
  else if FPendingClick then
    PositionCaretFromMouse(X, Y);    // no drag occurred -> reposition the caret

  FPendingClick := False;
end;

{ ---- mouse caret positioning: inverse of RecalcCaretPixel ---- }

function TTextControl.LogicalFromPoint(X, Y: Integer;
  SnapToNearest: Boolean): TPoint;
var
  Vr, Off: Integer;
  Row: TVisualRow;
begin
  // Not measured / nothing to map yet: fall back to the document start.
  if (FLayout = nil) or (FLineHeight <= 0) or (FContent.Count = 0) then
    Exit(Point(0, 0));

  // Screen -> content space (inverse of PlaceCaret's offset subtraction),
  // then content space -> visual row.
  Vr := (Y + ScrollOffsetY) div FLineHeight;
  if Vr < 0 then
    Vr := 0
  else if Vr > FLayout.Count - 1 then
    Vr := FLayout.Count - 1;

  Row := FLayout[Vr];

  // Column offset within the row. Subtract the left margin first (the clamp
  // below maps a click in the margin gutter to column 0). SnapToNearest rounds
  // to the closest boundary (caret placement); otherwise we floor to the
  // character under the cursor (selection anchor).
  if FCharWidth > 0 then
  begin
    if SnapToNearest then
      Off := (X - FLeftMargin + FCharWidth div 2) div FCharWidth
    else
      Off := (X - FLeftMargin) div FCharWidth;
  end
  else
    Off := 0;
  if Off < 0 then
    Off := 0
  else if Off > Row.Length then
    Off := Row.Length;

  Result := Point(Row.StartCol + Off, Row.LogicalLine);
end;

procedure TTextControl.PositionCaretFromMouse(X, Y: Integer);
var
  P: TPoint;
begin
  P := LogicalFromPoint(X, Y);
  SetCaret(P.Y, P.X);   // invariant A: the single clamped write
  SyncGoalCol;          // a click resets the preferred column (like typing)
  ReconcileCaret;       // recompute pixel once, scroll into view, place
  // No Invalidate: a click is a caret-only move (content unchanged); if it
  // scrolls, SetScrollY repaints. Same convention as KeyDown navigation.
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
    // The left margin steals columns from the text area.
    Cols := Max(1, (ViewportWidth - FLeftMargin) div FCharWidth)
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

procedure TTextControl.SetLeftMargin(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if FLeftMargin = AValue then
    Exit;
  FLeftMargin := AValue;
  RebuildLayout;        // the margin changes the wrap width
  RefreshCaret;         // and the caret's content-space pixel
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
  i, First, Last, LFirst, LLast: Integer;
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

  LFirst := MaxInt;
  LLast := -1;
  for i := First to Last do
  begin
    Row := FLayout[i];
    if Row.LogicalLine >= FContent.Count then
      Continue;

    DrawRow(Row, i * FLineHeight - ScrollOffsetY);

    if Row.LogicalLine < LFirst then LFirst := Row.LogicalLine;
    if Row.LogicalLine > LLast then LLast := Row.LogicalLine;
  end;

  // Drop token caches for lines that scrolled out of view (the console keeps
  // its immutable scrollback by overriding EvictTokens).
  if (FHighlighter <> nil) and (LLast >= LFirst) then
    EvictTokens(LFirst, LLast);

  // Reposition and restore the caret (recomputes pixel only if marked dirty).
  RefreshCaret;
  FCaret.ResumeAfterPaint;
end;

end.
