unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  uCodeEditor, uConsole, uHighlighterPython, uHighlighterSQL, uTheme,
  uAutoComplete;

type

  { TForm1 }

  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FCommandPanel: TPanel;
    FThemeCombo: TComboBox;
    FLoadButton: TButton;
    FSaveButton: TButton;
    FTestButton: TButton;
    FTopPanel: TPanel;
    FBottomPanel: TPanel;
    FSplitter: TSplitter;
    FEditor: TCodeEditor;
    FConsole: TConsole;
    FEditorAC: TAutoCompleteControl;
    FConsoleAC: TAutoCompleteControl;
    FHistory: TStringList;     // submitted commands
    FHistoryIndex: Integer;    // cursor into FHistory (Count = "current empty line")
    procedure BuildLayout;
    procedure SeedEditor;
    procedure SeedConsole;
    procedure ConsoleCommand(Sender: TObject; const ACommand: string);
    procedure ConsoleHistory(Sender: TObject; APrevious: Boolean);
    procedure ThemeChange(Sender: TObject);
    procedure LoadClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure EditorComplete(Sender: TObject; const APrefix: string; AItems: TStrings);
    procedure ConsoleComplete(Sender: TObject; const APrefix: string; AItems: TStrings);
  public
    destructor Destroy; override;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  BuildLayout;
  SeedEditor;
  SeedConsole;
end;

procedure TForm1.BuildLayout;
begin
  // Command bar across the very top: theme selector + load/save buttons.
  FCommandPanel := TPanel.Create(Self);
  FCommandPanel.Parent := Self;
  FCommandPanel.Align := alTop;
  FCommandPanel.Height := 60;
  FCommandPanel.BevelOuter := bvNone;

  FThemeCombo := TComboBox.Create(Self);
  FThemeCombo.Parent := FCommandPanel;
  FThemeCombo.Style := csDropDownList;         // selection only, no free text
  FThemeCombo.Items.Add('Dark');
  FThemeCombo.Items.Add('Light');
  FThemeCombo.ItemIndex := 0;                  // matches the controls' default (dark)
  FThemeCombo.Left := 8;
  FThemeCombo.Top := 8;
  FThemeCombo.Width := 120;
  FThemeCombo.OnChange := @ThemeChange;

  FLoadButton := TButton.Create(Self);
  FLoadButton.Parent := FCommandPanel;
  FLoadButton.Caption := 'Load';
  FLoadButton.Left := 140;
  FLoadButton.Top := 7;
  FLoadButton.Width := 80;
  FLoadButton.OnClick := @LoadClick;

  FSaveButton := TButton.Create(Self);
  FSaveButton.Parent := FCommandPanel;
  FSaveButton.Caption := 'Save';
  FSaveButton.Left := 228;
  FSaveButton.Top := 7;
  FSaveButton.Width := 80;
  FSaveButton.OnClick := @SaveClick;

  FTestButton := TButton.Create(Self);
  FTestButton.Parent := FCommandPanel;
  FTestButton.Caption := 'Test';
  FTestButton.Left := 318;
  FTestButton.Top := 7;
  FTestButton.Width := 80;
  FTestButton.OnClick := @TestClick;

  // Top panel hosts the code editor.
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := alTop;
  FTopPanel.Top := FCommandPanel.Height;       // below the command bar
  FTopPanel.Height := (ClientHeight - FCommandPanel.Height) div 2;
  FTopPanel.BevelOuter := bvNone;

  // Splitter sits just below the top panel and resizes the top/bottom split.
  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alTop;
  FSplitter.Top := FCommandPanel.Height + FTopPanel.Height;

  // Bottom panel fills the rest and hosts the console.
  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Align := alClient;
  FBottomPanel.BevelOuter := bvNone;

  FEditor := TCodeEditor.Create(Self);
  FEditor.Parent := FTopPanel;
  FEditor.Align := alClient;
  FEditor.WordWrap:= true;
  FEditor.Highlighter := PythonHighlighter;   // shared singleton

  FConsole := TConsole.Create(Self);
  FConsole.Parent := FBottomPanel;
  FConsole.Align := alClient;
  FConsole.Highlighter := SqlHighlighter;      // SQL console

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

  FConsole.OnCommand := @ConsoleCommand;
  FConsole.OnHistory := @ConsoleHistory;
  FConsole.Output('TConsole - terminal control. Type a command and press Enter.');
  FConsole.NewPrompt;
end;

procedure TForm1.ConsoleCommand(Sender: TObject; const ACommand: string);
begin
  // Remember the command, then reset the history cursor past the newest entry.
  if ACommand <> '' then
    FHistory.Add(ACommand);
  FHistoryIndex := FHistory.Count;

  // Host-driven: print a response, then show the next prompt.
  if ACommand <> '' then
    FConsole.Output('you typed: ' + ACommand + #13#10 + 'Good for you!');
  FConsole.NewPrompt;
end;

procedure TForm1.ConsoleHistory(Sender: TObject; APrevious: Boolean);
begin
  if FHistory.Count = 0 then
    Exit;

  if APrevious then
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
    FConsole.SetInput('')                   // past the newest entry -> empty line
  else
    FConsole.SetInput(FHistory[FHistoryIndex]);
end;

procedure TForm1.ThemeChange(Sender: TObject);
var
  Kind: TThemeKind;
begin
  // Both controls share the selected theme.
  if FThemeCombo.ItemIndex = 1 then
    Kind := thLight
  else
    Kind := thDark;
  FEditor.ThemeKind := Kind;
  FConsole.ThemeKind := Kind;
end;

procedure TForm1.LoadClick(Sender: TObject);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create('c:\temp\test.txt', fmOpenRead or fmShareDenyWrite);
  try
    FEditor.LoadFromStream(FS);
  finally
    FS.Free;
  end;
end;

procedure TForm1.SaveClick(Sender: TObject);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create('c:\temp\test.txt', fmCreate);
  try
    FEditor.SaveToStream(FS);
  finally
    FS.Free;
  end;
end;

procedure TForm1.TestClick(Sender: TObject);
begin
  FConsole.Prompt:= 'Dev Shmec';
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
  for i := 0 to High(Words) do
    if (APrefix = '') or SameText(Copy(Words[i], 1, Length(APrefix)), APrefix) then
      AItems.Add(Words[i]);
end;

destructor TForm1.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

end.
