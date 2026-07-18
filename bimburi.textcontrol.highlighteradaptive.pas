unit bimburi.textcontrol.highlighteradaptive;

{$mode delphi}{$H+}

interface

uses
  Classes, bimburi.textcontrol.highlighter;

type
  { The host returns the console's CURRENT prompt (e.g. FConsole.Prompt).
    Declared here rather than reusing the console's TGetPrompt so this unit
    stays independent of the console. }
  TAdaptivePromptFunc = function: string of object;

  { TAdaptiveHighlighter
    A dispatching highlighter for TConsole: it owns no lexing rules itself but
    routes each line to one of two children based on the line's first input
    character - '.' goes to DotHighlighter, anything else to
    DefaultHighlighter. Assigned once as the console's Highlighter, it makes
    the highlighting adaptive with NO changes to the controls:

    - Dispatch is a pure function of line content, evaluated at lex time, so
      the live input line re-dispatches automatically on every keystroke (the
      console re-lexes it per edit) and scrollback keeps the colouring each
      command was submitted with - the Highlighter property never changes, so
      the token cache is never flushed.
    - Command lines are stored as prompt+input; the prompt is stripped before
      dispatch and the child lexes only the input (a quote in the prompt must
      not open a string). Tokens are shifted back to full-line columns; the
      prompt region stays token-free - the console paints it in the prefix
      colour anyway. Every prompt ever reported is remembered, because
      scrollback lines keep the prompt that was current when they were
      submitted.
    - Lex state: a line arriving in a non-zero state is a continuation of an
      unterminated construct (e.g. an open SQL block comment), and the child
      owning that state keeps the whole line - first-char dispatch only
      applies from the normal state. Non-zero dot-child states are tagged
      with bit 7 so a continuation returns to the right child; consequently
      both children must keep their own states below $80 (SQL uses 0..1,
      dot commands are single-line and always end at 0). }
  TAdaptiveHighlighter = class(THighlighter)
  private
    FDefault: THighlighter;       // not owned (typically a shared singleton)
    FDotChild: THighlighter;      // not owned
    FOnGetPrompt: TAdaptivePromptFunc;
    FSeenPrompts: TStringList;    // every prompt ever seen, for scrollback
    function PromptLenOf(const ALine: string): Integer;
    function EncodeState(AChild: THighlighter; AState: TLexState): TLexState;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;

    property DefaultHighlighter: THighlighter read FDefault write FDefault;
    property DotHighlighter: THighlighter read FDotChild write FDotChild;
    property OnGetPrompt: TAdaptivePromptFunc read FOnGetPrompt write FOnGetPrompt;
  end;

implementation

const
  DotStateFlag = $80;   // bit 7 of TLexState marks "state owned by DotChild"

constructor TAdaptiveHighlighter.Create;
begin
  inherited Create;
  FSeenPrompts := TStringList.Create;
  FSeenPrompts.CaseSensitive := True;   // prompts are matched exactly
end;

destructor TAdaptiveHighlighter.Destroy;
begin
  FSeenPrompts.Free;
  inherited Destroy;
end;

function TAdaptiveHighlighter.PromptLenOf(const ALine: string): Integer;
var
  P: string;
  i, L: Integer;
begin
  // Learn the current prompt, then try every prompt ever seen against the
  // line start; the longest match wins (a prompt could be a prefix of an
  // older, longer one).
  if Assigned(FOnGetPrompt) then
  begin
    P := FOnGetPrompt();
    if (P <> '') and (FSeenPrompts.IndexOf(P) < 0) then
      FSeenPrompts.Add(P);
  end;
  Result := 0;
  for i := 0 to FSeenPrompts.Count - 1 do
  begin
    L := Length(FSeenPrompts[i]);
    if (L > Result) and (Copy(ALine, 1, L) = FSeenPrompts[i]) then
      Result := L;
  end;
end;

function TAdaptiveHighlighter.EncodeState(AChild: THighlighter;
  AState: TLexState): TLexState;
begin
  // 0 must stay 0 in every case, so the next line dispatches fresh.
  if AState = 0 then
    Result := 0
  else if AChild = FDotChild then
    Result := AState or DotStateFlag
  else
    Result := AState;   // default-child states pass through untagged
end;

procedure TAdaptiveHighlighter.ScanLine(const ALine: string;
  var AState: TLexState; var ATokens: TTokenArray; out ACount: Integer);
var
  Child: THighlighter;
  S: TLexState;
  Rest: string;
  PfxLen, i: Integer;
begin
  ACount := 0;

  // Continuation: the child owning the incoming state keeps the whole line
  // (including any prompt text - it IS inside the unterminated construct).
  if AState <> 0 then
  begin
    if (AState and DotStateFlag) <> 0 then
    begin
      Child := FDotChild;
      S := AState and not DotStateFlag;
    end
    else
    begin
      Child := FDefault;
      S := AState;
    end;
    if Child = nil then
    begin
      AState := 0;
      Exit;
    end;
    Child.ScanLine(ALine, S, ATokens, ACount);
    AState := EncodeState(Child, S);
    Exit;
  end;

  // Normal state: strip the prompt, dispatch on the input's first character.
  PfxLen := PromptLenOf(ALine);
  Rest := Copy(ALine, PfxLen + 1, MaxInt);
  if (Rest <> '') and (Rest[1] = '.') then
    Child := FDotChild
  else
    Child := FDefault;
  if Child = nil then
  begin
    AState := 0;
    Exit;
  end;

  S := 0;
  Child.ScanLine(Rest, S, ATokens, ACount);
  if PfxLen > 0 then
    for i := 0 to ACount - 1 do
      Inc(ATokens[i].StartCol, PfxLen);
  AState := EncodeState(Child, S);
end;

end.
