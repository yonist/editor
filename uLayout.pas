unit uLayout;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, uContent;

type
  { TVisualRow
    One displayed row. A logical line (TContent line) maps to one or more of
    these. StartCol/Length describe the slice of the logical line shown here. }
  TVisualRow = record
    LogicalLine: Integer;   // index into TContent
    StartCol: Integer;      // 0-based column offset within the logical line
    Length: Integer;        // number of characters on this visual row
  end;

  { TLayout
    The wrap layout: flattens the logical lines into a list of visual rows.
    This is the single source of truth for the logical<->visual mapping, shared
    by painting and the caret. It is rebuilt only when something that affects
    layout changes (content edit, resize, font change, wrap toggle).

    Soft wrap only: the logical text in TContent is never modified. }
  TLayout = class
  private
    FContent: TContent;
    FRows: array of TVisualRow;
    FCount: Integer;
    FWordWrap: Boolean;
    FWrapCols: Integer;     // available columns per visual row
    function GetRow(AIndex: Integer): TVisualRow;
    procedure AddRow(ALogicalLine, AStartCol, ALength: Integer);
    procedure WrapLine(ALogicalLine: Integer);
  public
    constructor Create(AContent: TContent);

    procedure SetParams(AWordWrap: Boolean; AWrapCols: Integer);
    procedure Rebuild;

    // Visual row index containing logical position (ALine, ACol), or -1.
    function VisualRowOf(ALogicalLine, ACol: Integer): Integer;

    property Count: Integer read FCount;
    property Rows[AIndex: Integer]: TVisualRow read GetRow; default;
  end;

implementation

constructor TLayout.Create(AContent: TContent);
begin
  inherited Create;
  FContent := AContent;
  FWordWrap := True;
  FWrapCols := 1;
end;

procedure TLayout.SetParams(AWordWrap: Boolean; AWrapCols: Integer);
begin
  FWordWrap := AWordWrap;
  if AWrapCols < 1 then
    FWrapCols := 1
  else
    FWrapCols := AWrapCols;
end;

function TLayout.GetRow(AIndex: Integer): TVisualRow;
begin
  Result := FRows[AIndex];
end;

procedure TLayout.AddRow(ALogicalLine, AStartCol, ALength: Integer);
begin
  if FCount = System.Length(FRows) then
  begin
    if FCount = 0 then
      SetLength(FRows, 64)
    else
      SetLength(FRows, FCount * 2);
  end;
  FRows[FCount].LogicalLine := ALogicalLine;
  FRows[FCount].StartCol := AStartCol;
  FRows[FCount].Length := ALength;
  Inc(FCount);
end;

procedure TLayout.WrapLine(ALogicalLine: Integer);
var
  S: string;
  L, Pos, W, MaxEnd, b, k: Integer;
begin
  S := FContent[ALogicalLine];
  L := System.Length(S);

  // An empty logical line still occupies one (empty) visual row.
  if L = 0 then
  begin
    AddRow(ALogicalLine, 0, 0);
    Exit;
  end;

  // Not wrapping, or the line fits: a single visual row covers it whole.
  if (not FWordWrap) or (L <= FWrapCols) then
  begin
    AddRow(ALogicalLine, 0, L);
    Exit;
  end;

  W := FWrapCols;
  Pos := 0;                          // 0-based column within the line
  while Pos < L do
  begin
    if L - Pos <= W then
    begin
      // Remainder fits on one row.
      AddRow(ALogicalLine, Pos, L - Pos);
      Pos := L;
    end
    else
    begin
      MaxEnd := Pos + W;             // exclusive end of the widest possible row

      // Look for the last space within [Pos .. MaxEnd-1] so we can break at a
      // word boundary instead of mid-word. (S is 1-based.)
      b := -1;
      for k := MaxEnd - 1 downto Pos do
        if S[k + 1] = ' ' then
        begin
          b := k;
          Break;
        end;

      if b < 0 then
      begin
        // A single word wider than the row: force-break it at the row edge.
        AddRow(ALogicalLine, Pos, W);
        Pos := MaxEnd;
      end
      else
      begin
        // Break after the space (the space stays on the current row).
        AddRow(ALogicalLine, Pos, b - Pos + 1);
        Pos := b + 1;
      end;
    end;
  end;
end;

procedure TLayout.Rebuild;
var
  i: Integer;
begin
  FCount := 0;

  if FContent.Count = 0 then
  begin
    AddRow(0, 0, 0);                 // always at least one visual row
    Exit;
  end;

  for i := 0 to FContent.Count - 1 do
    WrapLine(i);
end;

function TLayout.VisualRowOf(ALogicalLine, ACol: Integer): Integer;
var
  i, Last: Integer;
begin
  Last := -1;
  for i := 0 to FCount - 1 do
    if FRows[i].LogicalLine = ALogicalLine then
    begin
      // Caret inside this row's span.
      if (ACol >= FRows[i].StartCol) and
         (ACol < FRows[i].StartCol + FRows[i].Length) then
        Exit(i);
      // Track the furthest row that starts at/before ACol, for the case where
      // ACol sits at the very end of the logical line.
      if ACol >= FRows[i].StartCol then
        Last := i;
    end;
  Result := Last;
end;

end.
