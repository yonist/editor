unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  uCodeEditor, uConsole;

type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FTopPanel: TPanel;
    FBottomPanel: TPanel;
    FSplitter: TSplitter;
    FEditor: TCodeEditor;
    FConsole: TConsole;
    FHistory: TStringList;     // submitted commands
    FHistoryIndex: Integer;    // cursor into FHistory (Count = "current empty line")
    procedure BuildLayout;
    procedure SeedEditor;
    procedure SeedConsole;
    procedure ConsoleCommand(Sender: TObject; const ACommand: string);
    procedure ConsoleHistory(Sender: TObject; APrevious: Boolean);
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
  // Top panel hosts the code editor.
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := alTop;
  FTopPanel.Height := ClientHeight div 2;
  FTopPanel.BevelOuter := bvNone;

  // Splitter sits just below the top panel and resizes the top/bottom split.
  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alTop;
  FSplitter.Top := FTopPanel.Height;   // place it below the top panel

  // Bottom panel fills the rest and hosts the console.
  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Align := alClient;
  FBottomPanel.BevelOuter := bvNone;

  FEditor := TCodeEditor.Create(Self);
  FEditor.Parent := FTopPanel;
  FEditor.Align := alClient;
  FEditor.WordWrap:= true;

  FConsole := TConsole.Create(Self);
  FConsole.Parent := FBottomPanel;
  FConsole.Align := alClient;
end;

procedure TForm1.SeedEditor;
var
  I: Integer;
begin
  // Some sample text so we can see it painting.
  FEditor.Content.Add('program Hello;');
  FEditor.Content.Add('begin');
  FEditor.Content.Add('  WriteLn(''Hello, world!'');');
  FEditor.Content.Add('end.');
  FEditor.Content.Add('');
  FEditor.Content.Add('// A deliberately long line of text that should wrap across several visual rows when WordWrap is enabled, demonstrating the new soft word-wrapping layout.');
  FEditor.Content.Add('');

  // Enough lines to overflow the viewport so the scrollbar engages.
  for I := 1 to 40 do
    FEditor.Content.Add('Line ' + IntToStr(I) + ' - the quick brown fox jumps over the lazy dog.');

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

destructor TForm1.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

end.
