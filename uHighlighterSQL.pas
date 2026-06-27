unit uHighlighterSQL;

{$mode delphi}{$H+}

interface

uses
  uHighlighter;

type
  { TSqlHighlighter - case-insensitive keywords, -- and /* */ comments
    (block comments span lines via the state), '...' strings with '' escapes. }
  TSqlHighlighter = class(THighlighter)
  public
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
  end;

function SqlHighlighter: TSqlHighlighter;   // shared singleton

implementation

uses
  SysUtils;

const
  SQL_NORMAL = 0;
  SQL_BLOCK  = 1;   // inside an open /* ... */

  // Sorted, UPPERCASE (the scanned word is upcased before the binary search).
  SqlKeywords: array[0..68] of string = (
    'ADD','ALL','ALTER','AND','ANY','AS','ASC','BEGIN','BETWEEN','BY',
    'CASE','CAST','CHECK','COLUMN','COMMIT','CONSTRAINT','CREATE','CROSS',
    'DATABASE','DEFAULT','DELETE','DESC','DISTINCT','DROP','ELSE','END',
    'EXEC','EXISTS','FOREIGN','FROM','FULL','GROUP','HAVING','IN','INDEX',
    'INNER','INSERT','INTO','IS','JOIN','KEY','LEFT','LIKE','LIMIT','NOT',
    'NULL','ON','OR','ORDER','OUTER','PRIMARY','PROCEDURE','REFERENCES',
    'RIGHT','ROLLBACK','SELECT','SET','TABLE','THEN','TOP','TRUNCATE',
    'UNION','UNIQUE','UPDATE','VALUES','VIEW','WHEN','WHERE','WITH'
  );

var
  _Sql: TSqlHighlighter = nil;

function SqlHighlighter: TSqlHighlighter;
begin
  if _Sql = nil then
    _Sql := TSqlHighlighter.Create;
  Result := _Sql;
end;

procedure TSqlHighlighter.ScanLine(const ALine: string; var AState: TLexState;
  var ATokens: TTokenArray; out ACount: Integer);
var
  i, n, st: Integer;
  ch: Char;
  closed: Boolean;
begin
  ACount := 0;
  n := Length(ALine);
  i := 1;

  // Continue an open block comment from a previous line.
  if AState = SQL_BLOCK then
  begin
    st := i;
    closed := False;
    while i <= n do
    begin
      if (ALine[i] = '*') and (i < n) and (ALine[i + 1] = '/') then
      begin
        i := i + 2;
        closed := True;
        Break;
      end;
      Inc(i);
    end;
    AddToken(ATokens, ACount, st - 1, i - st, tkComment);
    if closed then
      AState := SQL_NORMAL
    else
    begin
      AState := SQL_BLOCK;
      Exit;
    end;
  end;

  while i <= n do
  begin
    ch := ALine[i];

    // line comment  --
    if (ch = '-') and (i < n) and (ALine[i + 1] = '-') then
    begin
      AddToken(ATokens, ACount, i - 1, n - i + 1, tkComment);
      Exit;
    end;

    // block comment  /* ... */
    if (ch = '/') and (i < n) and (ALine[i + 1] = '*') then
    begin
      st := i;
      i := i + 2;
      closed := False;
      while i <= n do
      begin
        if (ALine[i] = '*') and (i < n) and (ALine[i + 1] = '/') then
        begin
          i := i + 2;
          closed := True;
          Break;
        end;
        Inc(i);
      end;
      AddToken(ATokens, ACount, st - 1, i - st, tkComment);
      if not closed then
      begin
        AState := SQL_BLOCK;
        Exit;
      end;
      Continue;
    end;

    // string  '...'   ('' is an escaped quote)
    if ch = '''' then
    begin
      st := i;
      Inc(i);
      while i <= n do
      begin
        if ALine[i] = '''' then
        begin
          if (i < n) and (ALine[i + 1] = '''') then
            i := i + 2
          else
          begin
            Inc(i);
            Break;
          end;
        end
        else
          Inc(i);
      end;
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

    // identifier / keyword
    if IsIdentStart(ch) then
    begin
      st := i;
      while (i <= n) and IsIdentChar(ALine[i]) do
        Inc(i);
      if InSorted(UpperCase(Copy(ALine, st, i - st)), SqlKeywords) then
        AddToken(ATokens, ACount, st - 1, i - st, tkKeyword);
      Continue;
    end;

    Inc(i);
  end;
end;

initialization
finalization
  FreeAndNil(_Sql);
end.
