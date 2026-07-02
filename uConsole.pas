unit uConsole;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Types, LCLType, Clipbrd, uTextControl, uContent, uConsoleSpinner;

type
  // The host returns the mode from OnCommand: ccSync means it already produced
  // output and called NewPrompt; ccAsync means it will call CommandResult later
  // (the console spins and waits in the meantime).
  TConsoleCommandMode = (ccSync, ccAsync);
  TConsoleCommandEvent = function(Sender: TObject; const ACommand: string): TConsoleCommandMode of object;
  // APrevious = True -> older entry (Up); False -> newer entry (Down).
  TConsoleHistoryEvent = procedure(Sender: TObject; APrevious: Boolean) of object;
  // Raised when the user asks to cancel a running async command (Ctrl+C with no
  // selection). The host may ignore it or finish the command via CommandResult.
  TConsoleCancelEvent = procedure(Sender: TObject; const ACommand: string) of object;

  { TConsole
    A console/terminal control: an append-only scrollback of read-only history
    plus a single editable input line (a read-only prompt prefix followed by the
    text the user types). Enter submits the input line via OnCommand; the host
    then writes output with Output() and starts the next line with NewPrompt().

    Most of the read-only confinement comes from TTextControl.EditableStart. }
  TConsole = class(TTextControl)
  private
    FPrompt: string;
    FInputActive: Boolean;            // between NewPrompt and the next Enter
    FOnCommand: TConsoleCommandEvent;
    FOnHistory: TConsoleHistoryEvent;
    FOnCancelCommand: TConsoleCancelEvent;
    FSpinner: TConsoleSpinner;
    FSpinnerType: TConsoleSpinnerType;
    FAwaitingResult: Boolean;         // async command in flight (spinner running)
    FRunningCommand: string;          // the command currently awaiting a result
    FSpinnerLine: Integer;            // content line the spinner animates on (-1 = none)
    function LastLineIndex: Integer;
    function LastLine: string;
    procedure SetPrompt(AValue: string);
    procedure SpinnerWrite(const AText: unicodestring; const rewriteLine: Boolean);
    procedure StartSpinner;
    procedure StopSpinner;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function AcceptsKey(Key: Word; Shift: TShiftState): Boolean; override;
    function EditableStart: TPoint; override;
    procedure InsertChar(ACh: Char); override;
    procedure DeleteBack; override;
    procedure DeleteForward; override;
    procedure NewLine; override;      // Enter -> submit, not a line split
    function DoTab(ABack: Boolean): Boolean; override;   // consume Tab, do nothing
    procedure MoveUp; override;       // Up/Down don't move the caret; they
    procedure MoveDown; override;     // request history navigation instead
    procedure Paste; override;        // single-line input: strip line breaks
    procedure EvictTokens(AFirst, ALast: Integer); override;  // keep scrollback cached
    procedure PositionCaretFromMouse(X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // The console is a live terminal, not a document - refuse serialization.
    procedure SaveToStream(AStream: TStream); override;
    procedure LoadFromStream(AStream: TStream); override;

    // Program -> console: append read-only output (splits embedded newlines).
    procedure Output(const AText: string);
    // Begin a fresh editable input line.
    procedure NewPrompt;
    // The text typed on the current input line (prompt stripped).
    function CurrentInput: string;
    // Replace the editable input text (e.g. with a recalled history entry).
    procedure SetInput(const AText: string);
    // Async-command completion: the host calls this when its work finishes. It
    // stops the spinner, prints the result, and shows a new prompt.
    procedure CommandResult(const AResult: string);

    // Assigning Prompt starts a new editable line and renders the new prompt.
    property Prompt: string read FPrompt write SetPrompt;
    property InputActive: Boolean read FInputActive;
    // True while an async command is in flight (spinner running).
    property AwaitingResult: Boolean read FAwaitingResult;
    property SpinnerType: TConsoleSpinnerType read FSpinnerType write FSpinnerType;
    property OnCommand: TConsoleCommandEvent read FOnCommand write FOnCommand;
    property OnHistory: TConsoleHistoryEvent read FOnHistory write FOnHistory;
    // Ctrl+C during an async command (with nothing selected). The host decides:
    // ignore, or wrap it up with CommandResult.
    property OnCancelCommand: TConsoleCancelEvent read FOnCancelCommand write FOnCancelCommand;
  end;

implementation

constructor TConsole.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPrompt := '$ ';
  FInputActive := False;
  FSpinnerType := csClock;
  FSpinnerLine := -1;
  FSpinner := TConsoleSpinner.Create(SpinnerWrite);
end;

destructor TConsole.Destroy;
begin
  FSpinner.Free;   // its destructor stops/frees the timer
  inherited Destroy;
end;

procedure TConsole.SaveToStream(AStream: TStream);
begin
  raise Exception.Create('TConsole does not support SaveToStream');
end;

procedure TConsole.LoadFromStream(AStream: TStream);
begin
  raise Exception.Create('TConsole does not support LoadFromStream');
end;

function TConsole.LastLineIndex: Integer;
begin
  Result := Content.Count - 1;
end;

function TConsole.LastLine: string;
begin
  if Content.Count > 0 then
    Result := Content[Content.Count - 1]
  else
    Result := '';
end;

procedure TConsole.SetPrompt(AValue: string);
begin
  FPrompt := AValue;
  NewPrompt;   // setting the prompt renders it on a fresh input line
end;

function TConsole.AcceptsKey(Key: Word; Shift: TShiftState): Boolean;
begin
  if FInputActive then
    Exit(True);                         // normal editing while the prompt is live

  // Locked (between commands, or awaiting an async result): swallow everything
  // that could mutate content or open the completion popup. Read-only copy
  // conveniences stay available so the user can grab scrollback.
  Result := (ssCtrl in Shift) and
            ((Key = Ord('C')) or (Key = Ord('A')) or (Key = VK_INSERT));
end;

function TConsole.EditableStart: TPoint;
begin
  if Content.Count = 0 then
    Result := Point(0, 0)
  else if FInputActive then
    // Editable from just after the prompt on the last line.
    Result := Point(Length(FPrompt), LastLineIndex)
  else
    // Input locked: pin the boundary to the end of content (nothing editable).
    Result := Point(Length(LastLine), LastLineIndex);
end;

procedure TConsole.InsertChar(ACh: Char);
begin
  if not FInputActive then
    Exit;
  inherited InsertChar(ACh);
end;

procedure TConsole.DeleteBack;
begin
  if not FInputActive then
    Exit;
  inherited DeleteBack;               // base stops at the prompt boundary
end;

procedure TConsole.DeleteForward;
begin
  if not FInputActive then
    Exit;
  inherited DeleteForward;            // confined to the input line by the caret
end;

procedure TConsole.NewLine;
var
  Cmd: string;
  Mode: TConsoleCommandMode;
begin
  if not FInputActive then
    Exit;

  Cmd := CurrentInput;
  FInputActive := False;              // lock input; the host shows the next prompt
  ResetUndo;                          // the submitted line is now immutable history

  // The host decides per command whether it answered synchronously (it already
  // called Output/NewPrompt) or will deliver a result later via CommandResult.
  Mode := ccSync;
  if Assigned(FOnCommand) then
    Mode := FOnCommand(Self, Cmd);

  if Mode = ccAsync then
  begin
    FAwaitingResult := True;
    FRunningCommand := Cmd;            // remembered for a possible cancel
    StartSpinner;
  end;
end;

procedure TConsole.KeyDown(var Key: Word; Shift: TShiftState);
begin
  // While awaiting an async result, Ctrl+C with nothing selected is a cancel
  // request (there's nothing to copy). Hand it to the host and consume the key;
  // Ctrl+C with a selection still copies (falls through to the base).
  if FAwaitingResult and (ssCtrl in Shift) and (Key = Ord('C')) and
     not HasSelection then
  begin
    Key := 0;
    if Assigned(FOnCancelCommand) then
      FOnCancelCommand(Self, FRunningCommand);
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TConsole.SpinnerWrite(const AText: unicodestring;
  const rewriteLine: Boolean);
begin
  if rewriteLine and (FSpinnerLine >= 0) then
  begin
    SwapLines(FSpinnerLine, 1, [string(AText)]);      // animate in place
    RefreshView;
  end
  else
  begin
    SwapLines(Content.Count, 0, [string(AText)]);     // append the spinner line
    FSpinnerLine := LastLineIndex;                    // remember it for rewrites
    RefreshView;
    ScrollBottomIntoView;                             // bring the new line into view
  end;
end;

procedure TConsole.StartSpinner;
begin
  FSpinnerLine := -1;                 // next SpinnerWrite appends a fresh line
  FSpinner.Start(FSpinnerType);
end;

procedure TConsole.StopSpinner;
begin
  if FSpinner.IsActive then
    FSpinner.Stop;
  if FSpinnerLine >= 0 then
  begin
    SwapLines(FSpinnerLine, 1, []);   // remove the transient spinner line
    FSpinnerLine := -1;
    RefreshView;
  end;
end;

procedure TConsole.CommandResult(const AResult: string);
begin
  if not FAwaitingResult then
    Exit;                             // ignore late / duplicate results
  FAwaitingResult := False;
  FRunningCommand := '';
  StopSpinner;
  if AResult <> '' then
    Output(AResult);
  NewPrompt;
end;

function TConsole.DoTab(ABack: Boolean): Boolean;
begin
  Result := False;   // consume the Tab key but do nothing (for now)
end;

procedure TConsole.MoveUp;
begin
  // Up/Down are history recall, not caret navigation. Clearing the selection
  // here makes the base's post-move ExtendTo a no-op, so Shift+Up/Down never
  // start a selection.
  ClearSelection;
  if Assigned(FOnHistory) then
    FOnHistory(Self, True);          // previous (older) entry
end;

procedure TConsole.MoveDown;
begin
  ClearSelection;
  if Assigned(FOnHistory) then
    FOnHistory(Self, False);         // next (newer) entry
end;

procedure TConsole.Paste;
var
  S: string;
begin
  if not FInputActive then
    Exit;
  // The input is a single line: remove every line break from the pasted text.
  S := Clipboard.AsText;
  S := StringReplace(S, #13#10, '', [rfReplaceAll]);
  S := StringReplace(S, #10, '', [rfReplaceAll]);
  S := StringReplace(S, #13, '', [rfReplaceAll]);
  InsertText(S);
  AfterEdit;
end;

procedure TConsole.PositionCaretFromMouse(X, Y: Integer);
var
  P, ES: TPoint;
begin
  P := LogicalFromPoint(X, Y);
  ES := EditableStart;

  // Click in the read-only region (scrollback history, or the prompt prefix):
  // leave the caret exactly where it is. This is the inverse of the read-only
  // test in ClampCaret/DeleteBack.
  if (P.Y < ES.Y) or ((P.Y = ES.Y) and (P.X < ES.X)) then
    Exit;

  inherited PositionCaretFromMouse(X, Y);   // inside the input: reposition
end;

function TConsole.CurrentInput: string;
var
  S: string;
begin
  S := LastLine;
  if Copy(S, 1, Length(FPrompt)) = FPrompt then
    Result := Copy(S, Length(FPrompt) + 1, MaxInt)
  else
    Result := S;
end;

procedure TConsole.SetInput(const AText: string);
begin
  if not FInputActive then
    Exit;
  // Replace the input line (non-recorded); SwapLines invalidates the highlight.
  SwapLines(LastLineIndex, 1, [FPrompt + AText]);
  ResetUndo;                         // a recalled line is a fresh, non-recorded state
  RefreshView;                       // re-wrap first, so the caret maps correctly
  // Caret to end of input; SetPosition also scrolls it into view.
  Caret.SetPosition(LastLineIndex, Length(FPrompt) + Length(AText));
end;

procedure TConsole.Output(const AText: string);
var
  Lines: TStringList;
  Arr: array of string;
  i: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    SetLength(Arr, Lines.Count);
    for i := 0 to Lines.Count - 1 do
      Arr[i] := Lines[i];
    SwapLines(Content.Count, 0, Arr);   // append (non-recorded)
  finally
    Lines.Free;
  end;
  RefreshView;
end;

procedure TConsole.EvictTokens(AFirst, ALast: Integer);
begin
  // The scrollback is immutable, so its highlight data is cached for good; only
  // the input line is ever re-lexed (its own edits invalidate just itself).
  // Hence: never evict.
end;

procedure TConsole.NewPrompt;
begin
  SwapLines(Content.Count, 0, [FPrompt]);   // append the prompt line (non-recorded)
  FInputActive := True;
  ResetUndo;                         // undo is scoped to the current input line
  RefreshView;                       // re-wrap first, so the caret maps correctly
  // Caret just after the prompt; SetPosition also scrolls it into view.
  Caret.SetPosition(LastLineIndex, Length(FPrompt));
end;

end.
