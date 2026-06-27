unit uHighlighter;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Graphics;

type
  TTokenKind = (tkText, tkKeyword, tkIdentifier, tkString, tkComment, tkNumber,
    tkOperator);

  { TToken - a colored span within one logical line. }
  TToken = record
    StartCol: Integer;    // 0-based column
    Length: Integer;      // number of characters
    Kind: TTokenKind;
  end;

  TTokenArray = array of TToken;

  TLexState = Byte;       // 0 = normal; other values belong to the highlighter

  { TLineHL - the control's per-line highlight cache slot. State is always kept
    (cheap); Tokens may be released by eviction and re-lexed on demand. }
  TLineHL = record
    State: TLexState;     // lexer state at the START of this line
    Tokens: TTokenArray;  // cached tokens (released when HasTokens is False)
    Count: Integer;
    HasTokens: Boolean;
  end;
  TLineHLArray = array of TLineHL;

  TSyntaxColors = array[TTokenKind] of TColor;

  { THighlighter - a per-line state-machine lexer. Stateless apart from the
    in/out AState a line carries; the rule tables live in the concrete classes. }
  THighlighter = class
  protected
    class function IsIdentStart(C: Char): Boolean;
    class function IsIdentChar(C: Char): Boolean;
    procedure AddToken(var ATokens: TTokenArray; var ACount: Integer;
      AStartCol, ALength: Integer; AKind: TTokenKind);
    // Binary search over a sorted (CompareStr order) keyword list.
    function InSorted(const AWord: string; const AList: array of string): Boolean;
  public
    // Scan ALine starting in AState; write tokens into ATokens (reused, grown as
    // needed), return ACount and the end state back in AState.
    procedure ScanLine(const ALine: string; var AState: TLexState;
      var ATokens: TTokenArray; out ACount: Integer); virtual; abstract;
  end;

const
  DefaultSyntaxColors: TSyntaxColors = (
    clBlack,   // tkText
    clBlue,    // tkKeyword
    clBlack,   // tkIdentifier
    clGreen,   // tkString   (dark green in the LCL palette)
    clGray,    // tkComment
    clTeal,    // tkNumber
    clBlack    // tkOperator
  );

implementation

class function THighlighter.IsIdentStart(C: Char): Boolean;
begin
  Result := (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

class function THighlighter.IsIdentChar(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

procedure THighlighter.AddToken(var ATokens: TTokenArray; var ACount: Integer;
  AStartCol, ALength: Integer; AKind: TTokenKind);
begin
  if ALength <= 0 then
    Exit;
  if ACount = System.Length(ATokens) then
  begin
    if ACount = 0 then
      SetLength(ATokens, 32)
    else
      SetLength(ATokens, ACount * 2);
  end;
  ATokens[ACount].StartCol := AStartCol;
  ATokens[ACount].Length := ALength;
  ATokens[ACount].Kind := AKind;
  Inc(ACount);
end;

function THighlighter.InSorted(const AWord: string;
  const AList: array of string): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Lo := 0;
  Hi := High(AList);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := CompareStr(AWord, AList[Mid]);
    if C = 0 then
      Exit(True)
    else if C < 0 then
      Hi := Mid - 1
    else
      Lo := Mid + 1;
  end;
  Result := False;
end;

end.
