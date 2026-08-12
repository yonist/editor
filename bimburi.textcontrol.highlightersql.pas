unit bimburi.textcontrol.highlightersql;

{$mode delphi}{$H+}

interface

uses
  bimburi.textcontrol.highlighter;

type
  { TSqlHighlighter - case-insensitive keywords, -- and /* */ comments
    (block comments span lines via the state), '...' strings with '' escapes.

    The keyword set is INSTANCE state (dialects differ per database connection):
    the constructor seeds the common core below, and the host swaps in a
    dialect's set with SetKeywords when a connection is (re)established. }
  TSqlHighlighter = class(THighlighter)
  private
    FKeywords: array of string;   // active set: UPPERCASE, sorted, deduped
  public
    constructor Create;

    // Replace the active keyword set. AMergeCommon=True (the default) takes
    // CommonSqlKeywords + AKeywords - the normal "connected to a dialect" call;
    // False takes exactly AKeywords, for hosts whose dialect metadata is
    // complete on its own. Case, ordering and duplicates in AKeywords don't
    // matter: everything is upcased, sorted and deduped here.
    //
    // Deliberately NO cache invalidation happens on a keyword change: in the
    // console, already-painted scrollback keeps its cached tokens (lines stay
    // coloured with the dialect they were typed under - the keyword set does
    // not affect lex states, so the caches remain valid), while the live input
    // line re-lexes per keystroke and picks the new set up immediately. Two
    // caveats: (1) scrollback lines never yet painted lex with the NEW set
    // when first scrolled into view; (2) TCodeEditor evicts off-viewport
    // tokens, so mutating under an editor recolours gradually - for an editor,
    // assign a highlighter instance to Highlighter instead (full flush).
    procedure SetKeywords(const AKeywords: array of string;
      AMergeCommon: Boolean = True);

    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
  end;

const
  // The dialect-independent core, also the default set of a fresh instance.
  // Public so hosts can compose with it explicitly if they ever need to.
  CommonSqlKeywords: array[0..68] of string = (
    'ADD','ALL','ALTER','AND','ANY','AS','ASC','BEGIN','BETWEEN','BY',
    'CASE','CAST','CHECK','COLUMN','COMMIT','CONSTRAINT','CREATE','CROSS',
    'DATABASE','DEFAULT','DELETE','DESC','DISTINCT','DROP','ELSE','END',
    'EXEC','EXISTS','FOREIGN','FROM','FULL','GROUP','HAVING','IN','INDEX',
    'INNER','INSERT','INTO','IS','JOIN','KEY','LEFT','LIKE','LIMIT','NOT',
    'NULL','ON','OR','ORDER','OUTER','PRIMARY','PROCEDURE','REFERENCES',
    'RIGHT','ROLLBACK','SELECT','SET','TABLE','THEN','TOP','TRUNCATE',
    'UNION','UNIQUE','UPDATE','VALUES','VIEW','WHEN','WHERE','WITH'
  );

function SqlHighlighter: TSqlHighlighter;   // shared singleton

implementation

uses
  Classes, SysUtils;

const
  SQL_NORMAL = 0;
  SQL_BLOCK  = 1;   // inside an open /* ... */

var
  _Sql: TSqlHighlighter = nil;

function SqlHighlighter: TSqlHighlighter;
begin
  if _Sql = nil then
    _Sql := TSqlHighlighter.Create;
  Result := _Sql;
end;

constructor TSqlHighlighter.Create;
begin
  inherited Create;
  SetKeywords([]);                    // [] merged with the common core = the default set
end;

procedure TSqlHighlighter.SetKeywords(const AKeywords: array of string;
  AMergeCommon: Boolean);
var
  L: TStringList;
  S: string;
  i: Integer;
begin
  // Normalise through a sorted, deduping list so InSorted's binary search gets
  // exactly what it needs (UPPERCASE + CompareStr order) regardless of how the
  // host's dialect metadata is cased or ordered.
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    L.CaseSensitive := True;          // entries are upcased before Add
    if AMergeCommon then
      for S in CommonSqlKeywords do
        L.Add(S);                     // the core list is already uppercase
    for i := 0 to High(AKeywords) do
      L.Add(UpperCase(AKeywords[i]));
    SetLength(FKeywords, L.Count);
    for i := 0 to L.Count - 1 do
      FKeywords[i] := L[i];
  finally
    L.Free;
  end;
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
      if InSorted(UpperCase(Copy(ALine, st, i - st)), FKeywords) then
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
