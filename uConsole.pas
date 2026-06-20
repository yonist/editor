unit uConsole;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Types, uTextControl, uContent;

type
  TConsoleCommandEvent = procedure(Sender: TObject; const ACommand: string) of object;
  // APrevious = True -> older entry (Up); False -> newer entry (Down).
  TConsoleHistoryEvent = procedure(Sender: TObject; APrevious: Boolean) of object;

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
    function LastLineIndex: Integer;
    function LastLine: string;
  protected
    function EditableStart: TPoint; override;
    procedure InsertChar(ACh: Char); override;
    procedure DeleteBack; override;
    procedure DeleteForward; override;
    procedure NewLine; override;      // Enter -> submit, not a line split
    procedure MoveUp; override;       // Up/Down don't move the caret; they
    procedure MoveDown; override;     // request history navigation instead
    procedure PositionCaretFromMouse(X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;

    // Program -> console: append read-only output (splits embedded newlines).
    procedure Output(const AText: string);
    // Begin a fresh editable input line.
    procedure NewPrompt;
    // The text typed on the current input line (prompt stripped).
    function CurrentInput: string;
    // Replace the editable input text (e.g. with a recalled history entry).
    procedure SetInput(const AText: string);

    property Prompt: string read FPrompt write FPrompt;
    property InputActive: Boolean read FInputActive;
    property OnCommand: TConsoleCommandEvent read FOnCommand write FOnCommand;
    property OnHistory: TConsoleHistoryEvent read FOnHistory write FOnHistory;
  end;

implementation

constructor TConsole.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPrompt := '$ ';
  FInputActive := False;
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
begin
  if not FInputActive then
    Exit;

  Cmd := CurrentInput;
  FInputActive := False;              // lock input; the host shows the next prompt

  if Assigned(FOnCommand) then
    FOnCommand(Self, Cmd);
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
  Content[LastLineIndex] := FPrompt + AText;
  RefreshView;                       // re-wrap first, so the caret maps correctly
  // Caret to end of input; SetPosition also scrolls it into view.
  Caret.SetPosition(LastLineIndex, Length(FPrompt) + Length(AText));
end;

procedure TConsole.Output(const AText: string);
var
  Lines: TStringList;
  i: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for i := 0 to Lines.Count - 1 do
      Content.Add(Lines[i]);
  finally
    Lines.Free;
  end;
  RefreshView;
end;

procedure TConsole.NewPrompt;
begin
  Content.Add(FPrompt);
  FInputActive := True;
  RefreshView;                       // re-wrap first, so the caret maps correctly
  // Caret just after the prompt; SetPosition also scrolls it into view.
  Caret.SetPosition(LastLineIndex, Length(FPrompt));
end;

end.
