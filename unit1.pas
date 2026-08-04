unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  bimburi.textcontrol.codeeditor, bimburi.textcontrol.console,
  bimburi.textcontrol.highlighterpython, bimburi.textcontrol.highlightersql,
  bimburi.textcontrol.highlighteradaptive, bimburi.textcontrol.highlighterdot,
  bimburi.textcontrol.autocomplete, uOptionsPanel;

type

  { TForm1
    Test harness: the code editor on top, the console below, and next to each
    control a sidebar (uOptionsPanel) that toggles every option of that
    control, so each feature can be exercised by hand independently. }

  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FTopPanel: TPanel;
    FBottomPanel: TPanel;
    FSplitter: TSplitter;
    FEditor: TCodeEditor;
    FConsole: TConsole;
    FEditorAC: TAutoCompleteControl;
    FConsoleAC: TAutoCompleteControl;
    FEditorOptions: TEditorOptions;
    FConsoleOptions: TConsoleOptions;
    FAdaptive: TAdaptiveHighlighter;   // console: SQL, or dot-commands after '.'
    FHistory: TStringList;     // submitted commands
    FHistoryIndex: Integer;    // cursor into FHistory (Count = "current empty line")
    FAsyncTimer: TTimer;       // simulates a slow async command
    FAsyncCommand: string;     // command awaiting its async result
    procedure BuildLayout;
    procedure SeedEditor;
    procedure SeedConsole;
    function ConsoleCommand(const console: TConsole; const ACommand: string): TConsoleCommandMode;
    procedure AsyncDone(Sender: TObject);
    procedure ConsoleCancel(const Sender: TConsole; const ACommand: string);
    procedure ConsoleHistory(const Sender: TConsole; const prev: Boolean; var historyItem: string);
    procedure ConsoleBoot(const bootMessage: TStringList);
    function GetConsolePrompt: string;
    procedure EditorComplete(Sender: TObject; const APrefix: string; AItems: TStrings);
    procedure ConsoleComplete(Sender: TObject; const APrefix: string; AItems: TStrings);
  public
    destructor Destroy; override;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

const
  // The console's dot commands: one list drives both the dot-command
  // highlighter (known = keyword colour) and the '.'-mode autocomplete.
  DotCommands: array[0..12] of string = (
    'databases', 'dump', 'exit', 'headers', 'help', 'indexes', 'mode',
    'open', 'quit', 'read', 'schema', 'tables', 'timer');

procedure TForm1.FormCreate(Sender: TObject);
begin
  BuildLayout;
  SeedEditor;
  SeedConsole;
end;

procedure TForm1.BuildLayout;
begin
  // Top pane hosts the code editor (plus its options sidebar).
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := alTop;
  FTopPanel.Height := ClientHeight div 2;
  FTopPanel.BevelOuter := bvNone;

  // Splitter sits just below the top pane and resizes the top/bottom split.
  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alTop;
  FSplitter.Top := FTopPanel.Height;

  // Bottom pane fills the rest and hosts the console (plus its sidebar).
  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Align := alClient;
  FBottomPanel.BevelOuter := bvNone;

  FEditor := TCodeEditor.Create(Self);
  FEditor.Parent := FTopPanel;
  FEditor.Align := alClient;
  FEditor.WordWrap := True;
  FEditor.Highlighter := PythonHighlighter;   // shared singleton

  FConsole := TConsole.Create(Self);
  FConsole.Parent := FBottomPanel;
  FConsole.Align := alClient;

  // Adaptive highlighting: the console lexes SQL by default, but a line whose
  // input starts with '.' is coloured as a dot command. One highlighter is
  // assigned once; it dispatches per line (see bimburi.textcontrol.highlighteradaptive).
  DotCommandHighlighter.SetCommands(DotCommands);
  FAdaptive := TAdaptiveHighlighter.Create;
  FAdaptive.DefaultHighlighter := SqlHighlighter;
  FAdaptive.DotHighlighter := DotCommandHighlighter;
  FAdaptive.OnGetPrompt := @GetConsolePrompt;
  FConsole.Highlighter := FAdaptive;

  // Autocomplete popups (parented to the form so they can overflow the panes).
  FEditorAC := TAutoCompleteControl.Create(Self);
  FEditorAC.Parent := Self;
  FEditorAC.Editor := FEditor;
  FEditorAC.OnGetProp := @EditorComplete;
  FEditor.Completion := FEditorAC;

  FConsoleAC := TAutoCompleteControl.Create(Self);
  FConsoleAC.Parent := Self;
  FConsoleAC.Editor := FConsole;
  FConsoleAC.OnGetProp := @ConsoleComplete;
  FConsole.Completion := FConsoleAC;

  // Options sidebars: created last, so they pick up each control's final
  // state (highlighter, completion, ...) as the initial widget values.
  FEditorOptions := TEditorOptions.Create(Self, FEditor, FEditorAC);
  FEditorOptions.Parent := FTopPanel;
  FEditorOptions.Align := alRight;

  FConsoleOptions := TConsoleOptions.Create(Self, FConsole, FAdaptive,
    'Adaptive', FConsoleAC);
  FConsoleOptions.Parent := FBottomPanel;
  FConsoleOptions.Align := alRight;

  // Start with the console focused. This also exercises the initial-activation
  // caret path: the enter notification reaches the control before the OS focus
  // does (see TTextControl.UpdateCaretVisibility).
  ActiveControl := FConsole;
end;

procedure TForm1.SeedEditor;
var
  I: Integer;
begin
  // Sample Python so the highlighter has something to colour.
  FEditor.Content.Add('# greet.py - a tiny demo');
  FEditor.Content.Add('import sys');
  FEditor.Content.Add('');
  FEditor.Content.Add('def greet(name):');
  FEditor.Content.Add('    """Return a greeting for the given name."""');
  FEditor.Content.Add('    if name == "":');
  FEditor.Content.Add('        return ''Hello, world!''');
  FEditor.Content.Add('    return f''Hello, {name}!''   # 42 is not the answer here');
  FEditor.Content.Add('');
  FEditor.Content.Add('for i in range(40):');
  FEditor.Content.Add('    print(greet(str(i)), i * 3.14)');
  FEditor.Content.Add('');

  // Enough lines to overflow the viewport so the scrollbar engages.
  for I := 1 to 40 do
    FEditor.Content.Add('x = ' + IntToStr(I) + '   # comment for line ' + IntToStr(I));

  // Start the caret at the end of the last line.
  FEditor.Caret.SetPosition(FEditor.Content.Count - 1,
    Length(FEditor.Content[FEditor.Content.Count - 1]));
end;

procedure TForm1.SeedConsole;
begin
  FHistory := TStringList.Create;
  FHistoryIndex := 0;

  FAsyncTimer := TTimer.Create(Self);
  FAsyncTimer.Enabled := False;
  FAsyncTimer.Interval := 2000;                 // pretend the work takes 2s
  FAsyncTimer.OnTimer := @AsyncDone;

  FConsole.OnCommand := @ConsoleCommand;
  FConsole.OnHistory := @ConsoleHistory;
  FConsole.OnCancelCommand := @ConsoleCancel;
  FConsole.OnBoot := @ConsoleBoot;              // intro lines emitted on Activate
  // The host must call Activate once the console is wired up: it emits the boot
  // message (via OnBoot) and shows the first prompt.
  FConsole.Activate;
end;

procedure TForm1.ConsoleBoot(const bootMessage: TStringList);
begin
  bootMessage.Add('TConsole - terminal control. Type a command and press Enter.');
  bootMessage.Add('Type "async" to see a spinner while a slow command runs.');
  bootMessage.Add('Lines starting with "." switch to dot-command colours and completion.');
end;

function TForm1.GetConsolePrompt: string;
begin
  Result := FConsole.Prompt;    // the adaptive highlighter strips it per line
end;

function TForm1.ConsoleCommand(const console: TConsole;
  const ACommand: string): TConsoleCommandMode;
begin
  // Remember the command, then reset the history cursor past the newest entry.
  if ACommand <> '' then
    FHistory.Add(ACommand);
  FHistoryIndex := FHistory.Count;

  // "async" (optionally with parameters, e.g. "async SELECT"): kick off slow
  // work and let the console spin until AsyncDone fires.
  if SameText(ACommand, 'async') or SameText(Copy(ACommand, 1, 6), 'async ') then
  begin
    FAsyncCommand := ACommand;
    FAsyncTimer.Enabled := True;
    Result := ccAsync;                          // console shows the spinner
    Exit;
  end;

  // Synchronous: print a response now and show the next prompt ourselves.
  //if ACommand <> '' then
  //  FConsole.Output('you typed: ' + ACommand + #13#10 + 'Good for you!');
  //Result := ccSync;
end;

procedure TForm1.AsyncDone(Sender: TObject);
begin
  FAsyncTimer.Enabled := False;                 // one-shot
  FConsole.CommandResult('async result for: ' + FAsyncCommand);

end;

procedure TForm1.ConsoleCancel(const Sender: TConsole; const ACommand: string);
begin
  // Host's choice: abort the simulated work and close out the command.
  FAsyncTimer.Enabled := False;
  FConsole.CommandResult('^C  cancelled: ' + ACommand);
end;

procedure TForm1.ConsoleHistory(const Sender: TConsole; const prev: Boolean;
  var historyItem: string);
begin
  // The console applies historyItem to the input line itself (SetInput); we only
  // move the cursor and hand back the entry to show.
  if FHistory.Count = 0 then
  begin
    historyItem := Sender.CurrentInput;     // no history -> leave the line unchanged
    Exit;
  end;

  if prev then
  begin
    if FHistoryIndex > 0 then
      Dec(FHistoryIndex);
  end
  else
  begin
    if FHistoryIndex < FHistory.Count then
      Inc(FHistoryIndex);
  end;

  if FHistoryIndex >= FHistory.Count then
    historyItem := ''                       // past the newest entry -> empty line
  else
    historyItem := FHistory[FHistoryIndex];
end;

procedure TForm1.EditorComplete(Sender: TObject; const APrefix: string;
  AItems: TStrings);
const
  Words: array[0..24] of string = (
    'def', 'class', 'import', 'from', 'return', 'print', 'range', 'len', 'for',
    'while', 'if', 'elif', 'else', 'try', 'except', 'finally', 'lambda', 'yield',
    'with', 'as', 'True', 'False', 'None', 'self', '__init__');
var
  i: Integer;
begin
  for i := 0 to High(Words) do
    if (APrefix = '') or SameText(Copy(Words[i], 1, Length(APrefix)), APrefix) then
      AItems.Add(Words[i]);
end;

procedure TForm1.ConsoleComplete(Sender: TObject; const APrefix: string;
  AItems: TStrings);
const
  Words: array[0..24] of string = (
    'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
    'DELETE', 'CREATE', 'TABLE', 'DROP', 'JOIN', 'INNER', 'LEFT', 'RIGHT',
    'ORDER', 'BY', 'GROUP', 'HAVING', 'AND', 'OR', 'NOT', 'NULL', 'LIKE');
var
  i: Integer;
begin
  // Adaptive completion: '.' input completes dot commands, anything else SQL.
  // '.' is not a word character, so for ".he" the prefix is "he" and accepting
  // an item replaces just the word - the dot stays; hence items carry no dot.
  if Copy(FConsole.CurrentInput, 1, 1) = '.' then
  begin
    for i := 0 to High(DotCommands) do
      if (APrefix = '') or SameText(Copy(DotCommands[i], 1, Length(APrefix)), APrefix) then
        AItems.Add(DotCommands[i]);
    Exit;
  end;

  for i := 0 to High(Words) do
    if (APrefix = '') or SameText(Copy(Words[i], 1, Length(APrefix)), APrefix) then
      AItems.Add(Words[i]);
end;

destructor TForm1.Destroy;
begin
  if Assigned(FAsyncTimer) then
    FAsyncTimer.Enabled := False;   // stop a stray tick during teardown
  FHistory.Free;
  inherited Destroy;
  // After inherited: the console (an owned component, holding a non-owning
  // reference to this highlighter) is gone by now.
  FAdaptive.Free;
end;

end.
