unit bimburi.textcontrol.highlighterdot;

{$mode delphi}{$H+}

interface

uses
  bimburi.textcontrol.highlighter;

type
  TKnownWordFunc = function(const AName: string): Boolean of object;

  { TDotCommandHighlighter - single-line lexer for "<sigil>command arg"
    console input: '.' for the dot commands (sqlite-style), '@' for the saved
    scripts. The "<sigil>name" head is tkKeyword when the name is known
    (plain tkIdentifier otherwise, so typos stay uncoloured); after it:
    -f/--flag as tkComment (visually muted - operator shares the text colour
    in both themes), quoted strings and numbers as usual, bare words plain.
    Sigil commands never span lines, so the end state is always 0. }
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
  i, n, st: Integer;
  ch, q: Char;
  Kind: TTokenKind;
begin
  ACount := 0;
  AState := 0;                    // single-line by construction
  n := Length(ALine);
  i := 1;

  // "<sigil>name" head at the very start of the input.
  if (n >= 1) and (ALine[1] = FSigil) then
  begin
    i := 2;
    while (i <= n) and IsIdentChar(ALine[i]) do
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

    // quoted argument ('...' or "..."); unterminated runs to end of line
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

    // number
    if (ch >= '0') and (ch <= '9') then
    begin
      st := i;
      while (i <= n) and (ALine[i] in ['0'..'9', '.']) do
        Inc(i);
      AddToken(ATokens, ACount, st - 1, i - st, tkNumber);
      Continue;
    end;

    // -f / --flag
    if ch = '-' then
    begin
      st := i;
      while (i <= n) and ((ALine[i] = '-') or IsIdentChar(ALine[i])) do
        Inc(i);
      AddToken(ATokens, ACount, st - 1, i - st, tkComment);
      Continue;
    end;

    // bare words and everything else render plain
    Inc(i);
  end;
end;

initialization
finalization
  FreeAndNil(_Dot);
  FreeAndNil(_At);
end.
