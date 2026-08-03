unit bimburi.textcontrol.highlighterjson;

{$mode delphi}{$H+}

interface

uses
  bimburi.textcontrol.highlighter;

type
  { TJsonHighlighter - strict JSON: "..." strings (object keys coloured as
    keywords, value strings as strings), numbers, and the true/false/null
    literals (coloured as numbers - i.e. constants). JSON has no comments and
    its strings cannot span lines, so the lexer is stateless (state stays 0). }
  TJsonHighlighter = class(THighlighter)
  public
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
  end;

function JsonHighlighter: TJsonHighlighter;   // shared singleton

implementation

uses
  SysUtils;

const
  // Sorted in CompareStr (ASCII) order.
  JsonLiterals: array[0..2] of string = ('false', 'null', 'true');

var
  _Json: TJsonHighlighter = nil;

function JsonHighlighter: TJsonHighlighter;
begin
  if _Json = nil then
    _Json := TJsonHighlighter.Create;
  Result := _Json;
end;

procedure TJsonHighlighter.ScanLine(const ALine: string; var AState: TLexState;
  var ATokens: TTokenArray; out ACount: Integer);
var
  i, n, st, j: Integer;
  ch: Char;
begin
  ACount := 0;
  AState := 0;                         // JSON needs no cross-line state
  n := Length(ALine);
  i := 1;

  while i <= n do
  begin
    ch := ALine[i];

    // string - "..." with \ escapes. JSON strings never span lines, so an
    // unterminated one simply runs to the end of the line.
    if ch = '"' then
    begin
      st := i;
      Inc(i);
      while (i <= n) and (ALine[i] <> '"') do
      begin
        if (ALine[i] = '\') and (i < n) then
          Inc(i, 2)                    // skip the escaped character
        else
          Inc(i);
      end;
      if i <= n then
        Inc(i);                        // include the closing quote

      // A string followed by ':' (ignoring whitespace) is an object key;
      // colour keys as keywords so they stand apart from value strings.
      j := i;
      while (j <= n) and (ALine[j] in [' ', #9]) do
        Inc(j);
      if (j <= n) and (ALine[j] = ':') then
        AddToken(ATokens, ACount, st - 1, i - st, tkKeyword)
      else
        AddToken(ATokens, ACount, st - 1, i - st, tkString);
      Continue;
    end;

    // number - approximate JSON number: -?digits(.digits)?(e[+-]digits)?
    // (a '-' only opens a number when a digit follows).
    if ((ch >= '0') and (ch <= '9')) or
       ((ch = '-') and (i < n) and (ALine[i + 1] in ['0'..'9'])) then
    begin
      st := i;
      if ch = '-' then
        Inc(i);
      while (i <= n) and (ALine[i] in ['0'..'9', '.', 'e', 'E', '+', '-']) do
        Inc(i);
      AddToken(ATokens, ACount, st - 1, i - st, tkNumber);
      Continue;
    end;

    // true / false / null. Any other bare word is invalid JSON - left plain.
    if IsIdentStart(ch) then
    begin
      st := i;
      while (i <= n) and IsIdentChar(ALine[i]) do
        Inc(i);
      if InSorted(Copy(ALine, st, i - st), JsonLiterals) then
        AddToken(ATokens, ACount, st - 1, i - st, tkNumber);
      Continue;
    end;

    // Structural punctuation ({ } [ ] : ,) is left to the plain text colour.
    Inc(i);
  end;
end;

initialization
finalization
  FreeAndNil(_Json);
end.
