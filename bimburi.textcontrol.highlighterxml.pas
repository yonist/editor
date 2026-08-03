unit bimburi.textcontrol.highlighterxml;

{$mode delphi}{$H+}

interface

uses
  bimburi.textcontrol.highlighter;

type
  { TXmlHighlighter - tag names as keywords, attribute names as numbers (the
    palette's "constant" colour), quoted attribute values as strings, &entity;
    references as numbers, <!-- --> comments and <![CDATA[ ]]> sections as
    comment/string. Comments, CDATA sections, tags and even quoted attribute
    values may span lines - the construct is carried in the lex state. Plain
    character data stays the default text colour.

    All states stay below $80 so the adaptive dispatcher can tag them. }
  TXmlHighlighter = class(THighlighter)
  private
    // Lex attribute space inside a tag, from column i until '>' (leaves the
    // state XML_NORMAL) or the end of the line (leaves it XML_INTAG, or the
    // open-quote states when a value is unterminated).
    procedure ScanInTag(const ALine: string; var i: Integer;
      var AState: TLexState; var ATokens: TTokenArray; var ACount: Integer);
  public
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); override;
  end;

function XmlHighlighter: TXmlHighlighter;   // shared singleton

implementation

uses
  SysUtils;

const
  XML_NORMAL   = 0;   // character data
  XML_COMMENT  = 1;   // inside <!-- -->
  XML_CDATA    = 2;   // inside <![CDATA[ ]]>
  XML_INTAG    = 3;   // inside a tag, between attributes
  XML_INTAG_SQ = 4;   // inside a tag, in an open '...' attribute value
  XML_INTAG_DQ = 5;   // inside a tag, in an open "..." attribute value

var
  _Xml: TXmlHighlighter = nil;

function XmlHighlighter: TXmlHighlighter;
begin
  if _Xml = nil then
    _Xml := TXmlHighlighter.Create;
  Result := _Xml;
end;

function IsNameStart(C: Char): Boolean;
begin
  Result := (C = '_') or (C = ':') or
            ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function IsNameChar(C: Char): Boolean;
begin
  Result := IsNameStart(C) or (C = '-') or (C = '.') or
            ((C >= '0') and (C <= '9'));
end;

// First position of ASub in ALine at or after AFrom (1-based), 0 if absent.
function IndexOfFrom(const ALine, ASub: string; AFrom: Integer): Integer;
var
  i, n, m: Integer;
begin
  n := Length(ALine);
  m := Length(ASub);
  for i := AFrom to n - m + 1 do
    if Copy(ALine, i, m) = ASub then
      Exit(i);
  Result := 0;
end;

procedure TXmlHighlighter.ScanInTag(const ALine: string; var i: Integer;
  var AState: TLexState; var ATokens: TTokenArray; var ACount: Integer);
var
  n, st: Integer;
  ch, q: Char;
begin
  n := Length(ALine);
  while i <= n do
  begin
    ch := ALine[i];

    if ch = '>' then
    begin
      Inc(i);
      AState := XML_NORMAL;
      Exit;
    end;

    // quoted attribute value; may run off the line (legal in XML)
    if (ch = '"') or (ch = '''') then
    begin
      q := ch;
      st := i;
      Inc(i);
      while (i <= n) and (ALine[i] <> q) do
        Inc(i);
      if i <= n then
      begin
        Inc(i);                        // include the closing quote
        AddToken(ATokens, ACount, st - 1, i - st, tkString);
        Continue;
      end;
      AddToken(ATokens, ACount, st - 1, i - st, tkString);
      if q = '"' then AState := XML_INTAG_DQ else AState := XML_INTAG_SQ;
      Exit;
    end;

    // attribute name
    if IsNameStart(ch) then
    begin
      st := i;
      while (i <= n) and IsNameChar(ALine[i]) do
        Inc(i);
      AddToken(ATokens, ACount, st - 1, i - st, tkNumber);
      Continue;
    end;

    Inc(i);                            // '=', '/', '?', whitespace, ...
  end;
  AState := XML_INTAG;                 // line ended inside the tag
end;

procedure TXmlHighlighter.ScanLine(const ALine: string; var AState: TLexState;
  var ATokens: TTokenArray; out ACount: Integer);
var
  i, n, st, k, ns: Integer;
  ch, q: Char;
begin
  ACount := 0;
  n := Length(ALine);
  i := 1;

  // Resume a construct left open by a previous line.
  case AState of
    XML_COMMENT:
      begin
        k := IndexOfFrom(ALine, '-->', 1);
        if k = 0 then
        begin
          AddToken(ATokens, ACount, 0, n, tkComment);
          Exit;                        // still inside the comment
        end;
        AddToken(ATokens, ACount, 0, k + 2, tkComment);
        i := k + 3;
        AState := XML_NORMAL;
      end;
    XML_CDATA:
      begin
        k := IndexOfFrom(ALine, ']]>', 1);
        if k = 0 then
        begin
          AddToken(ATokens, ACount, 0, n, tkString);
          Exit;
        end;
        AddToken(ATokens, ACount, 0, k + 2, tkString);
        i := k + 3;
        AState := XML_NORMAL;
      end;
    XML_INTAG_SQ, XML_INTAG_DQ:
      begin
        if AState = XML_INTAG_SQ then q := '''' else q := '"';
        st := i;
        while (i <= n) and (ALine[i] <> q) do
          Inc(i);
        if i > n then
        begin
          AddToken(ATokens, ACount, st - 1, i - st, tkString);
          Exit;                        // value still open
        end;
        Inc(i);                        // include the closing quote
        AddToken(ATokens, ACount, st - 1, i - st, tkString);
        AState := XML_INTAG;
        ScanInTag(ALine, i, AState, ATokens, ACount);
        if AState <> XML_NORMAL then
          Exit;
      end;
    XML_INTAG:
      begin
        ScanInTag(ALine, i, AState, ATokens, ACount);
        if AState <> XML_NORMAL then
          Exit;
      end;
  end;

  while i <= n do
  begin
    ch := ALine[i];

    if ch = '<' then
    begin
      // comment
      if Copy(ALine, i, 4) = '<!--' then
      begin
        st := i;
        k := IndexOfFrom(ALine, '-->', i + 4);
        if k = 0 then
        begin
          AddToken(ATokens, ACount, st - 1, n - st + 1, tkComment);
          AState := XML_COMMENT;
          Exit;
        end;
        AddToken(ATokens, ACount, st - 1, k + 3 - st, tkComment);
        i := k + 3;
        Continue;
      end;

      // CDATA section - raw character data, coloured as a string
      if Copy(ALine, i, 9) = '<![CDATA[' then
      begin
        st := i;
        k := IndexOfFrom(ALine, ']]>', i + 9);
        if k = 0 then
        begin
          AddToken(ATokens, ACount, st - 1, n - st + 1, tkString);
          AState := XML_CDATA;
          Exit;
        end;
        AddToken(ATokens, ACount, st - 1, k + 3 - st, tkString);
        i := k + 3;
        Continue;
      end;

      // tag: <name ...>, </name>, <?pi ...?>, <!DOCTYPE ...>
      Inc(i);
      if (i <= n) and (ALine[i] in ['/', '?', '!']) then
        Inc(i);
      if (i <= n) and IsNameStart(ALine[i]) then
      begin
        ns := i;
        while (i <= n) and IsNameChar(ALine[i]) do
          Inc(i);
        AddToken(ATokens, ACount, ns - 1, i - ns, tkKeyword);
      end;
      ScanInTag(ALine, i, AState, ATokens, ACount);
      if AState <> XML_NORMAL then
        Exit;                          // the tag runs onto the next line
      Continue;
    end;

    // &entity; reference in character data
    if ch = '&' then
    begin
      st := i;
      Inc(i);
      while (i <= n) and (ALine[i] in ['#', '0'..'9', 'A'..'Z', 'a'..'z']) do
        Inc(i);
      if (i <= n) and (ALine[i] = ';') then
      begin
        Inc(i);
        AddToken(ATokens, ACount, st - 1, i - st, tkNumber);
      end;
      Continue;                        // malformed '&...' stays plain
    end;

    Inc(i);                            // plain character data
  end;
end;

initialization
finalization
  FreeAndNil(_Xml);
end.
