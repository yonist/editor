unit uOptionsPanel;

{$mode delphi}{$H+}

interface

{ Test-harness sidebars for the demo form (Unit1).

  TTextControlOptions is a scrollable panel of toggles for every feature the
  two controls share through TTextControl (theme, highlighter, word wrap,
  read-only, gutter, autocomplete, tabs, margins, font size, undo/redo).
  TEditorOptions and TConsoleOptions extend it with the features specific to
  each control. The panel reads the control's current state when it is built,
  so create it after the control is fully wired up (highlighter, completion). }

uses
  Classes, SysUtils, Controls, Forms, Graphics, StdCtrls, ExtCtrls, Spin,
  Dialogs,
  bimburi.textcontrol.textcontrol, bimburi.textcontrol.codeeditor,
  bimburi.textcontrol.console, bimburi.textcontrol.theme,
  bimburi.textcontrol.highlighter, bimburi.textcontrol.highlighterpython,
  bimburi.textcontrol.highlightersql, bimburi.textcontrol.highlighterjson,
  bimburi.textcontrol.highlighterxml,
  bimburi.textcontrol.consolespinner,
  bimburi.textcontrol.autocomplete;

type

  { TTextControlOptions }

  TTextControlOptions = class(TScrollBox)
  private
    FTarget: TTextControl;
    FNextTop: Integer;
    FSavedCompletion: IAutoComplete;   // held while the checkbox disables it
    FCustomHL: THighlighter;           // optional 4th highlighter combo entry
    FCustomHLName: string;             // (e.g. the console's adaptive one)
    // The concrete popup, for the AutoOpen/MinChars rows. Held separately from
    // FSavedCompletion because the IAutoComplete interface deliberately doesn't
    // expose those properties (they are popup UI policy, not editor contract).
    FPopup: TAutoCompleteControl;
    FThemeCombo: TComboBox;
    FHighlighterCombo: TComboBox;
    FWordWrapCheck: TCheckBox;
    FReadOnlyCheck: TCheckBox;
    FShowGutterCheck: TCheckBox;
    FAutoCompleteCheck: TCheckBox;
    FAutoOpenCheck: TCheckBox;
    FTabSpacesCheck: TCheckBox;
    FGutterIntervalSpin: TSpinEdit;
    FMinCharsSpin: TSpinEdit;
    FTabWidthSpin: TSpinEdit;
    FFontSizeSpin: TSpinEdit;
    FLeftMarginSpin: TSpinEdit;
    FTopMarginSpin: TSpinEdit;
    procedure ThemeChange(Sender: TObject);
    procedure HighlighterChange(Sender: TObject);
    procedure WordWrapChange(Sender: TObject);
    procedure ReadOnlyChange(Sender: TObject);
    procedure ShowGutterChange(Sender: TObject);
    procedure GutterIntervalChange(Sender: TObject);
    procedure AutoCompleteChange(Sender: TObject);
    procedure AutoOpenChange(Sender: TObject);
    procedure MinCharsChange(Sender: TObject);
    procedure TabWidthChange(Sender: TObject);
    procedure TabSpacesChange(Sender: TObject);
    procedure FontSizeChange(Sender: TObject);
    procedure LeftMarginChange(Sender: TObject);
    procedure TopMarginChange(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    function HighlighterIndex: Integer;
  protected
    const
      Pad      = 8;     // left edge of labels/checkboxes
      RowH     = 34;    // vertical pitch between rows
      CtlLeft  = 140;   // x of the value control in label+control rows
      CtlWidth = 92;

    { Row builders. Each drops a control at FNextTop and advances it.
      Handlers are assigned after the initial value so building never fires. }
    function AddTitle(const ACaption: string): TLabel;
    function AddCheck(const ACaption: string; AChecked: Boolean;
      AOnChange: TNotifyEvent): TCheckBox;
    function AddCombo(const ACaption: string; const AItems: array of string;
      AItemIndex: Integer; AOnChange: TNotifyEvent): TComboBox;
    function AddSpin(const ACaption: string; AMin, AMax, AValue: Integer;
      AOnChange: TNotifyEvent): TSpinEdit;
    function AddEdit(const ACaption, AText: string): TEdit;
    function AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
    procedure AddButtonPair(const ACaption1: string; AOnClick1: TNotifyEvent;
      const ACaption2: string; AOnClick2: TNotifyEvent);

    { Builds the shared rows; descendants override to append their own. }
    procedure BuildRows; virtual;
  public
    // ACustomHL/ACustomHLName: an extra host-owned highlighter offered in the
    // combo besides the None/Python/SQL singletons. APopup: the control's
    // autocomplete popup; when passed, the sidebar also offers its
    // AutoOpen/MinChars policy rows.
    constructor Create(AOwner: TComponent; ATarget: TTextControl;
      const ATitle: string; ACustomHL: THighlighter = nil;
      const ACustomHLName: string = '';
      APopup: TAutoCompleteControl = nil); reintroduce;
    property Target: TTextControl read FTarget;
  end;

  { TEditorOptions - adds load/save, the editor's only extra surface }

  TEditorOptions = class(TTextControlOptions)
  private
    function Editor: TCodeEditor;
    procedure LoadClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
  protected
    procedure BuildRows; override;
  public
    constructor Create(AOwner: TComponent; ATarget: TCodeEditor;
      APopup: TAutoCompleteControl = nil); reintroduce;
  end;

  { TConsoleOptions - adds prompt text and spinner style }

  TConsoleOptions = class(TTextControlOptions)
  private
    FPromptEdit: TEdit;
    function Console: TConsole;
    procedure ApplyPromptClick(Sender: TObject);
    procedure SpinnerChange(Sender: TObject);
  protected
    procedure BuildRows; override;
  public
    constructor Create(AOwner: TComponent; ATarget: TConsole;
      ACustomHL: THighlighter = nil;
      const ACustomHLName: string = '';
      APopup: TAutoCompleteControl = nil); reintroduce;
  end;

implementation

{ TTextControlOptions }

constructor TTextControlOptions.Create(AOwner: TComponent;
  ATarget: TTextControl; const ATitle: string; ACustomHL: THighlighter;
  const ACustomHLName: string; APopup: TAutoCompleteControl);
begin
  inherited Create(AOwner);
  FTarget := ATarget;
  FSavedCompletion := ATarget.Completion;
  FCustomHL := ACustomHL;
  FCustomHLName := ACustomHLName;
  FPopup := APopup;
  Width := 260;
  HorzScrollBar.Visible := False;      // rows are sized to fit; only scroll down
  VertScrollBar.Increment := RowH;
  FNextTop := Pad;
  AddTitle(ATitle);
  BuildRows;
end;

function TTextControlOptions.HighlighterIndex: Integer;
begin
  if FTarget.Highlighter = THighlighter(PythonHighlighter) then
    Result := 1
  else if FTarget.Highlighter = THighlighter(SqlHighlighter) then
    Result := 2
  else if FTarget.Highlighter = THighlighter(JsonHighlighter) then
    Result := 3
  else if FTarget.Highlighter = THighlighter(XmlHighlighter) then
    Result := 4
  else if (FCustomHL <> nil) and (FTarget.Highlighter = FCustomHL) then
    Result := 5
  else
    Result := 0;
end;

procedure TTextControlOptions.BuildRows;
begin
  FThemeCombo := AddCombo('Theme', ['Dark', 'Light'],
    Ord(FTarget.ThemeKind = thLight), ThemeChange);
  // Combo built without a handler: the custom entry must be appended before
  // the initial index (possibly 5) is applied.
  FHighlighterCombo := AddCombo('Highlighter',
    ['None', 'Python', 'SQL', 'JSON', 'XML'], -1, nil);
  if FCustomHL <> nil then
    FHighlighterCombo.Items.Add(FCustomHLName);
  FHighlighterCombo.ItemIndex := HighlighterIndex;
  FHighlighterCombo.OnChange := HighlighterChange;
  FWordWrapCheck := AddCheck('Word wrap', FTarget.WordWrap, WordWrapChange);
  FReadOnlyCheck := AddCheck('Read-only', FTarget.ReadOnly, ReadOnlyChange);
  FAutoCompleteCheck := AddCheck('Autocomplete',
    FTarget.Completion <> nil, AutoCompleteChange);
  if FPopup <> nil then
  begin
    FAutoOpenCheck := AddCheck('AC auto open', FPopup.AutoOpen,
      AutoOpenChange);
    FMinCharsSpin := AddSpin('AC min chars', 1, 10, FPopup.MinChars,
      MinCharsChange);
  end;
  FShowGutterCheck := AddCheck('Show gutter', FTarget.ShowGutter,
    ShowGutterChange);
  FGutterIntervalSpin := AddSpin('Gutter interval', 1, 100,
    FTarget.GutterInterval, GutterIntervalChange);
  FTabWidthSpin := AddSpin('Tab width', 1, 16, FTarget.TabWidth,
    TabWidthChange);
  FTabSpacesCheck := AddCheck('Tab as spaces', FTarget.TabAsSpaces,
    TabSpacesChange);
  FFontSizeSpin := AddSpin('Font size', 6, 48, FTarget.Font.Size,
    FontSizeChange);
  FLeftMarginSpin := AddSpin('Left margin', 0, 100, FTarget.LeftMargin,
    LeftMarginChange);
  FTopMarginSpin := AddSpin('Top margin', 0, 100, FTarget.TopMargin,
    TopMarginChange);
  AddButtonPair('Undo', UndoClick, 'Redo', RedoClick);
end;

{ ---- row builders ---- }

function TTextControlOptions.AddTitle(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Left := Pad;
  Result.Top := FNextTop;
  Result.Caption := ACaption;
  Result.Font.Style := [fsBold];
  Inc(FNextTop, RowH);
end;

function TTextControlOptions.AddCheck(const ACaption: string;
  AChecked: Boolean; AOnChange: TNotifyEvent): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Self;
  Result.Left := Pad;
  Result.Top := FNextTop;
  Result.Caption := ACaption;
  Result.Checked := AChecked;
  Result.OnChange := AOnChange;
  Inc(FNextTop, RowH);
end;

function TTextControlOptions.AddCombo(const ACaption: string;
  const AItems: array of string; AItemIndex: Integer;
  AOnChange: TNotifyEvent): TComboBox;
var
  L: TLabel;
  S: string;
begin
  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Left := Pad;
  L.Top := FNextTop + 4;
  L.Caption := ACaption;

  Result := TComboBox.Create(Self);
  Result.Parent := Self;
  Result.Style := csDropDownList;
  Result.Left := CtlLeft;
  Result.Top := FNextTop;
  Result.Width := CtlWidth;
  for S in AItems do
    Result.Items.Add(S);
  Result.ItemIndex := AItemIndex;
  Result.OnChange := AOnChange;
  Inc(FNextTop, RowH);
end;

function TTextControlOptions.AddSpin(const ACaption: string;
  AMin, AMax, AValue: Integer; AOnChange: TNotifyEvent): TSpinEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Left := Pad;
  L.Top := FNextTop + 4;
  L.Caption := ACaption;

  Result := TSpinEdit.Create(Self);
  Result.Parent := Self;
  Result.Left := CtlLeft;
  Result.Top := FNextTop;
  Result.Width := CtlWidth;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := AValue;
  Result.OnChange := AOnChange;
  Inc(FNextTop, RowH);
end;

function TTextControlOptions.AddEdit(const ACaption, AText: string): TEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Left := Pad;
  L.Top := FNextTop + 4;
  L.Caption := ACaption;

  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.Left := CtlLeft;
  Result.Top := FNextTop;
  Result.Width := CtlWidth;
  Result.Text := AText;
  Inc(FNextTop, RowH);
end;

function TTextControlOptions.AddButton(const ACaption: string;
  AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Left := Pad;
  Result.Top := FNextTop;
  Result.Width := CtlLeft + CtlWidth - Pad;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  Inc(FNextTop, RowH);
end;

procedure TTextControlOptions.AddButtonPair(const ACaption1: string;
  AOnClick1: TNotifyEvent; const ACaption2: string; AOnClick2: TNotifyEvent);
var
  B: TButton;
  W: Integer;
begin
  W := (CtlLeft + CtlWidth - Pad - 6) div 2;

  B := TButton.Create(Self);
  B.Parent := Self;
  B.Left := Pad;
  B.Top := FNextTop;
  B.Width := W;
  B.Caption := ACaption1;
  B.OnClick := AOnClick1;

  B := TButton.Create(Self);
  B.Parent := Self;
  B.Left := Pad + W + 6;
  B.Top := FNextTop;
  B.Width := W;
  B.Caption := ACaption2;
  B.OnClick := AOnClick2;

  Inc(FNextTop, RowH);
end;

{ ---- shared handlers ---- }

procedure TTextControlOptions.ThemeChange(Sender: TObject);
begin
  if FThemeCombo.ItemIndex = 1 then
    FTarget.ThemeKind := thLight
  else
    FTarget.ThemeKind := thDark;
end;

procedure TTextControlOptions.HighlighterChange(Sender: TObject);
begin
  case FHighlighterCombo.ItemIndex of
    1: FTarget.Highlighter := PythonHighlighter;
    2: FTarget.Highlighter := SqlHighlighter;
    3: FTarget.Highlighter := JsonHighlighter;
    4: FTarget.Highlighter := XmlHighlighter;
    5: FTarget.Highlighter := FCustomHL;
  else
    FTarget.Highlighter := nil;      // plain text
  end;
end;

procedure TTextControlOptions.WordWrapChange(Sender: TObject);
begin
  FTarget.WordWrap := FWordWrapCheck.Checked;
end;

procedure TTextControlOptions.ReadOnlyChange(Sender: TObject);
begin
  FTarget.ReadOnly := FReadOnlyCheck.Checked;
end;

procedure TTextControlOptions.ShowGutterChange(Sender: TObject);
begin
  FTarget.ShowGutter := FShowGutterCheck.Checked;
end;

procedure TTextControlOptions.GutterIntervalChange(Sender: TObject);
begin
  FTarget.GutterInterval := FGutterIntervalSpin.Value;
end;

procedure TTextControlOptions.AutoCompleteChange(Sender: TObject);
begin
  if FAutoCompleteCheck.Checked then
    FTarget.Completion := FSavedCompletion
  else
  begin
    // Remember the popup so re-checking restores it.
    if FTarget.Completion <> nil then
      FSavedCompletion := FTarget.Completion;
    FTarget.Completion := nil;
  end;
end;

procedure TTextControlOptions.AutoOpenChange(Sender: TObject);
begin
  FPopup.AutoOpen := FAutoOpenCheck.Checked;
end;

procedure TTextControlOptions.MinCharsChange(Sender: TObject);
begin
  FPopup.MinChars := FMinCharsSpin.Value;
end;

procedure TTextControlOptions.TabWidthChange(Sender: TObject);
begin
  FTarget.TabWidth := FTabWidthSpin.Value;
  FTarget.Invalidate;                // TabWidth has no setter; repaint ourselves
end;

procedure TTextControlOptions.TabSpacesChange(Sender: TObject);
begin
  FTarget.TabAsSpaces := FTabSpacesCheck.Checked;
end;

procedure TTextControlOptions.FontSizeChange(Sender: TObject);
begin
  FTarget.Font.Size := FFontSizeSpin.Value;
end;

procedure TTextControlOptions.LeftMarginChange(Sender: TObject);
begin
  FTarget.LeftMargin := FLeftMarginSpin.Value;
end;

procedure TTextControlOptions.TopMarginChange(Sender: TObject);
begin
  FTarget.TopMargin := FTopMarginSpin.Value;
end;

procedure TTextControlOptions.UndoClick(Sender: TObject);
begin
  FTarget.Undo;
  FTarget.SetFocus;
end;

procedure TTextControlOptions.RedoClick(Sender: TObject);
begin
  FTarget.Redo;
  FTarget.SetFocus;
end;

{ TEditorOptions }

constructor TEditorOptions.Create(AOwner: TComponent; ATarget: TCodeEditor;
  APopup: TAutoCompleteControl);
begin
  inherited Create(AOwner, ATarget, 'Code editor', nil, '', APopup);
end;

function TEditorOptions.Editor: TCodeEditor;
begin
  Result := TCodeEditor(Target);
end;

procedure TEditorOptions.BuildRows;
begin
  inherited BuildRows;
  AddButtonPair('Load...', LoadClick, 'Save...', SaveClick);
end;

procedure TEditorOptions.LoadClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  FS: TFileStream;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'Text files|*.txt;*.py;*.sql|All files|*.*';
    if not Dlg.Execute then
      Exit;
    try
      FS := TFileStream.Create(Dlg.FileName, fmOpenRead or fmShareDenyWrite);
      try
        Editor.LoadFromStream(FS);
      finally
        FS.Free;
      end;
    except
      on E: Exception do
        ShowMessage('Load failed: ' + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TEditorOptions.SaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  FS: TFileStream;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'Text files|*.txt|All files|*.*';
    Dlg.DefaultExt := 'txt';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    try
      FS := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        Editor.SaveToStream(FS);
      finally
        FS.Free;
      end;
    except
      on E: Exception do
        ShowMessage('Save failed: ' + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

{ TConsoleOptions }

constructor TConsoleOptions.Create(AOwner: TComponent; ATarget: TConsole;
  ACustomHL: THighlighter; const ACustomHLName: string;
  APopup: TAutoCompleteControl);
begin
  inherited Create(AOwner, ATarget, 'Console', ACustomHL, ACustomHLName, APopup);
end;

function TConsoleOptions.Console: TConsole;
begin
  Result := TConsole(Target);
end;

procedure TConsoleOptions.BuildRows;
begin
  inherited BuildRows;
  FPromptEdit := AddEdit('Prompt', Console.Prompt);
  AddButton('Apply prompt', ApplyPromptClick);
  AddCombo('Spinner', ['Dots', 'Dots 4', 'Pipes', 'Clock'],
    Ord(Console.SpinnerType), SpinnerChange);
end;

procedure TConsoleOptions.ApplyPromptClick(Sender: TObject);
begin
  Console.Prompt := FPromptEdit.Text;
  Console.SetFocus;
end;

procedure TConsoleOptions.SpinnerChange(Sender: TObject);
begin
  // Takes effect on the next async command ("async" in the demo).
  Console.SpinnerType := TConsoleSpinnerType((Sender as TComboBox).ItemIndex);
end;

end.
