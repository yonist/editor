unit uHighlighterPython;

{$mode delphi}{$H+}

interface

uses
  uHighlighter;

type
  { TPythonHighlighter - case-sensitive keywords, # comments, '...'/"..."
    strings, and triple-quoted strings that span lines via the state. }
  TPythonHighlighter = class(THighlighter)
  public
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
  end;

function PythonHighlighter: TPythonHighlighter;   // shared singleton

implementation

uses
  SysUtils;

const
  PY_NORMAL    = 0;
  PY_TRIPLE_SQ = 1;   // inside an open '''
  PY_TRIPLE_DQ = 2;   // inside an open """

  // Sorted in CompareStr (ASCII) order: capitalised names sort before lowercase.
  PyKeywords: array[0..34] of string = (
    'False','None','True',
    'and','as','assert','async','await','break','class','continue','def',
    'del','elif','else','except','finally','for','from','global','if',
    'import','in','is','lambda','nonlocal','not','or','pass','raise',
    'return','try','while','with','yield'
  );

var
  _Py: TPythonHighlighter = nil;

function PythonHighlighter: TPythonHighlighter;
begin
  if _Py = nil then
    _Py := TPythonHighlighter.Create;
  Result := _Py;
end;

procedure TPythonHighlighter.ScanLine(const ALine: string; var AState: TLexState;
  var ATokens: TTokenArray; out ACount: Integer);
var
  i, n, st: Integer;
  ch, q: Char;
  closed: Boolean;
begin
  ACount := 0;
  n := Length(ALine);
  i := 1;

  // Continue an open triple-quoted string from a previous line.
  if AState <> PY_NORMAL then
  begin
    if AState = PY_TRIPLE_SQ then q := '''' else q := '"';
    st := i;
    closed := False;
    while i <= n do
    begin
      if (ALine[i] = q) and (i + 1 <= n) and (ALine[i + 1] = q) and
         (i + 2 <= n) and (ALine[i + 2] = q) then
      begin
        i := i + 3;
        closed := True;
        Break;
      end;
      Inc(i);
    end;
    AddToken(ATokens, ACount, st - 1, i - st, tkString);
    if closed then
      AState := PY_NORMAL
    else
      Exit;
  end;

  while i <= n do
  begin
    ch := ALine[i];

    // line comment  #
    if ch = '#' then
    begin
      AddToken(ATokens, ACount, i - 1, n - i + 1, tkComment);
      Exit;
    end;

    if (ch = '''') or (ch = '"') then
    begin
      q := ch;
      // triple-quoted string?
      if (i + 1 <= n) and (ALine[i + 1] = q) and (i + 2 <= n) and (ALine[i + 2] = q) then
      begin
        st := i;
        i := i + 3;
        closed := False;
        while i <= n do
        begin
          if (ALine[i] = q) and (i + 1 <= n) and (ALine[i + 1] = q) and
             (i + 2 <= n) and (ALine[i + 2] = q) then
          begin
            i := i + 3;
            closed := True;
            Break;
          end;
          Inc(i);
        end;
        AddToken(ATokens, ACount, st - 1, i - st, tkString);
        if not closed then
        begin
          if q = '''' then AState := PY_TRIPLE_SQ else AState := PY_TRIPLE_DQ;
          Exit;
        end;
        Continue;
      end
      else
      begin
        // single-line string ('\' escapes the next character)
        st := i;
        Inc(i);
        while (i <= n) and (ALine[i] <> q) do
        begin
          if (ALine[i] = '\') and (i < n) then
            Inc(i, 2)
          else
            Inc(i);
        end;
        if i <= n then
          Inc(i);            // include the closing quote
        AddToken(ATokens, ACount, st - 1, i - st, tkString);
        Continue;
      end;
    end;

    // number (approximate: also accepts hex/exponent characters)
    if (ch >= '0') and (ch <= '9') then
    begin
      st := i;
      while (i <= n) and (ALine[i] in ['0'..'9', '.', '_', 'x', 'X', 'o', 'O',
        'a'..'f', 'A'..'F']) do
        Inc(i);
      AddToken(ATokens, ACount, st - 1, i - st, tkNumber);
      Continue;
    end;

    // identifier / keyword
    if IsIdentStart(ch) then
    begin
      st := i;
      while (i <= n) and IsIdentChar(ALine[i]) do
        Inc(i);
      if InSorted(Copy(ALine, st, i - st), PyKeywords) then
        AddToken(ATokens, ACount, st - 1, i - st, tkKeyword);
      Continue;
    end;

    Inc(i);
  end;
end;

initialization
finalization
  FreeAndNil(_Py);
end.
