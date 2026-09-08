unit bimburi.textcontrol.highlighterdot;

{$mode delphi}{$H+}

interface

uses
  bimburi.textcontrol.highlighter;

type
  TKnownWordFunc = function(const AName: string): Boolean of object;

  { TDotCommandHighlighter - single-line lexer for "<sigil>command arg"
    console input: '.' for the dot commands (sqlite-style), '@' for the saved
    scripts. The "<sigil>name" head (hyphens included, so ".clear-list" is ONE
    name) is tkKeyword when the name is known (plain tkIdentifier otherwise,
    so typos stay uncoloured).

    Arguments are quoted strings (tkString, may span spaces) or whitespace-
    delimited segments consumed ATOMICALLY - a rule can never fire mid-word,
    so "q123" is one plain word, never plain-q + number-123. A segment splits
    once at its first '=': the left side is a flag when it starts with '-'
    (tkComment - visually muted), the value is tkNumber only when numeric as
    a WHOLE ("12312" yes, "123abc" no), and a quote ends a segment so
    "--name='two words'" hands the value to the string rule. Everything else
    is plain. Sigil commands never span lines, so the end state is always 0. }
  TDotCommandHighlighter = class(THighlighter)
  private
    FSigil: Char;                 // the first character the head starts with
    FCommands: array of string;   // known command names, without the sigil
    FOnKnownWord: TKnownWordFunc; // dynamic alternative to the list (scripts)
    function KnownCommand(const AName: string): Boolean;
  public
    constructor Create(ASigil: Char = '.');
    // Empty list (the default) = every "<sigil>name" counts as known.
    procedure SetCommands(const AList: array of string);
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
    // When assigned, consulted instead of the list (names that change at
    // runtime, like the saved scripts)
    property OnKnownWord: TKnownWordFunc read FOnKnownWord write FOnKnownWord;
  end;

function DotCommandHighlighter: TDotCommandHighlighter;   // shared singleton, '.'
function AtCommandHighlighter: TDotCommandHighlighter;    // shared singleton, '@'

implementation

uses
  SysUtils;

var
  _Dot: TDotCommandHighlighter = nil;
  _At: TDotCommandHighlighter = nil;

function DotCommandHighlighter: TDotCommandHighlighter;
begin
  if _Dot = nil then
    _Dot := TDotCommandHighlighter.Create('.');
  Result := _Dot;
end;

function AtCommandHighlighter: TDotCommandHighlighter;
begin
  if _At = nil then
    _At := TDotCommandHighlighter.Create('@');
  Result := _At;
end;

constructor TDotCommandHighlighter.Create(ASigil: Char);
begin
  inherited Create;
  FSigil := ASigil;
end;

procedure TDotCommandHighlighter.SetCommands(const AList: array of string);
var
  i: Integer;
begin
  SetLength(FCommands, Length(AList));
  for i := 0 to High(AList) do
    FCommands[i] := AList[i];
end;

function TDotCommandHighlighter.KnownCommand(const AName: string): Boolean;
var
  i: Integer;
begin
  if Assigned(FOnKnownWord) then
    Exit(FOnKnownWord(AName));
  if Length(FCommands) = 0 then
    Exit(True);
  for i := 0 to High(FCommands) do        // ~a dozen entries: linear is fine
    if SameText(AName, FCommands[i]) then
      Exit(True);
  Result := False;
end;

procedure TDotCommandHighlighter.ScanLine(const ALine: string;
  var AState: TLexState; var ATokens: TTokenArray; out ACount: Integer);
var
  i, n, st, SegEnd, Eq, k: Integer;
  ch, q: Char;
  Kind: TTokenKind;

  // Entirely digits/dots with at least one digit ("12", "1.5"; not "123abc",
  // not "."). The whole-value test is deliberate: a command line is not SQL,
  // and a half-coloured word ("q" plain + "123" green) is worse than an
  // uncoloured number. AFrom..ATo-1 are 1-based columns.
  function IsNumeric(AFrom, ATo: Integer): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    for j := AFrom to ATo - 1 do
      if ALine[j] in ['0'..'9'] then
        Result := True             // at least one digit seen
      else if ALine[j] <> '.' then
        Exit(False);
  end;

begin
  ACount := 0;
  AState := 0;                    // single-line by construction
  n := Length(ALine);
  i := 1;

  // "<sigil>name" head at the very start of the input. The name alphabet
  // includes '-' so hyphenated commands (".clear-list") are one name, both
  // for colouring and for the KnownCommand lookup.
  if (n >= 1) and (ALine[1] = FSigil) then
  begin
    i := 2;
    while (i <= n) and (IsIdentChar(ALine[i]) or (ALine[i] = '-')) do
      Inc(i);
    if KnownCommand(Copy(ALine, 2, i - 2)) then
      Kind := tkKeyword
    else
      Kind := tkIdentifier;
    AddToken(ATokens, ACount, 0, i - 1, Kind);
  end;

  while i <= n do
  begin
    ch := ALine[i];

    // quoted argument ('...' or "..."); may span spaces; unterminated runs
    // to end of line
    if (ch = '''') or (ch = '"') then
    begin
      q := ch;
      st := i;
      Inc(i);
      while (i <= n) and (ALine[i] <> q) do
        Inc(i);
      if i <= n then
        Inc(i);                   // include the closing quote
      AddToken(ATokens, ACount, st - 1, i - st, tkString);
      Continue;
    end;

    if (ch = ' ') or (ch = #9) then
    begin
      Inc(i);
      Continue;
    end;

    // One segment, consumed atomically: up to whitespace or an opening quote
    // (so "--name='two words'" leaves the value to the string rule above).
    st := i;
    while (i <= n) and not (ALine[i] in [' ', #9, '''', '"']) do
      Inc(i);
    SegEnd := i;                  // exclusive

    // Split once at the segment's first '=' ("--param=12312", "--a=b=c").
    Eq := 0;
    for k := st to SegEnd - 1 do
      if ALine[k] = '=' then
      begin
        Eq := k;
        Break;
      end;

    if Eq > 0 then
    begin
      if ALine[st] = '-' then                          // -f/--flag=value
        AddToken(ATokens, ACount, st - 1, Eq - st, tkComment);
      if (Eq + 1 < SegEnd) and IsNumeric(Eq + 1, SegEnd) then
        AddToken(ATokens, ACount, Eq, SegEnd - Eq - 1, tkNumber);
      // the '=' itself, non-numeric values, and a non-flag left side stay plain
    end
    else if ALine[st] = '-' then                       // -f / --flag
      AddToken(ATokens, ACount, st - 1, SegEnd - st, tkComment)
    else if IsNumeric(st, SegEnd) then                 // whole-numeric argument
      AddToken(ATokens, ACount, st - 1, SegEnd - st, tkNumber);
    // else: plain bare word - no token
  end;
end;

initialization
finalization
  FreeAndNil(_Dot);
  FreeAndNil(_At);
end.
