unit bimburi.textcontrol.highlighterdot;

{$mode delphi}{$H+}

interface

uses
  bimburi.textcontrol.highlighter;

type
  { TDotCommandHighlighter - single-line lexer for ".command arg" console
    input (sqlite-style dot commands). The ".name" head is tkKeyword when the
    name is a known command (plain tkIdentifier otherwise, so typos stay
    uncoloured); after it: -f/--flag as tkComment (visually muted - operator
    shares the text colour in both themes), quoted strings and numbers as
    usual, bare words plain. Dot commands never span lines, so the end state
    is always 0. }
  TDotCommandHighlighter = class(THighlighter)
  private
    FCommands: array of string;   // known command names, without the dot
    function KnownCommand(const AName: string): Boolean;
  public
    // Empty list (the default) = every ".name" counts as known.
    procedure SetCommands(const AList: array of string);
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
  end;

function DotCommandHighlighter: TDotCommandHighlighter;   // shared singleton

implementation

uses
  SysUtils;

var
  _Dot: TDotCommandHighlighter = nil;

function DotCommandHighlighter: TDotCommandHighlighter;
begin
  if _Dot = nil then
    _Dot := TDotCommandHighlighter.Create;
  Result := _Dot;
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

  // ".name" head at the very start of the input.
  if (n >= 1) and (ALine[1] = '.') then
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
end.
