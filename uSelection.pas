unit uSelection;

{$mode delphi}{$H+}

interface

type
  { TSelection
    A text selection, held as two logical positions in content coordinates:
      - Anchor: where the selection started (the fixed end).
      - Active: the moving end (extended as the mouse drags).
    Both are 0-based (Line, Col). The selection is independent of the caret -
    the host never moves the caret on the host's behalf when selecting.

    This class is pure logical geometry: ordering, emptiness and per-line
    column spans. Text extraction and painting live in the host, which owns
    the content and the canvas. }
  TSelection = class
  private
    FAnchorLine, FAnchorCol: Integer;
    FActiveLine, FActiveCol: Integer;
    FActive: Boolean;                 // a selection has been started
    procedure Normalize(out SLine, SCol, ELine, ECol: Integer);
  public
    // Begin a selection at (collapsed onto) a single point.
    procedure SetAnchor(ALine, ACol: Integer);
    // Move the active end (no-op if no selection has been started).
    procedure ExtendTo(ALine, ACol: Integer);
    // Drop the selection entirely.
    procedure Clear;

    // True when there is nothing to show/copy (not started, or collapsed).
    function IsEmpty: Boolean;

    // The selection in document order (line first, then col).
    procedure GetRange(out SLine, SCol, ELine, ECol: Integer);

    // The selected column span [C0, C1) on logical line ALine (length ALineLen).
    // Returns False if the line is wholly outside the selection or the span is
    // empty.
    function RangeOnLine(ALine, ALineLen: Integer; out C0, C1: Integer): Boolean;
  end;

implementation

procedure TSelection.SetAnchor(ALine, ACol: Integer);
begin
  FAnchorLine := ALine;
  FAnchorCol := ACol;
  FActiveLine := ALine;
  FActiveCol := ACol;
  FActive := True;
end;

procedure TSelection.ExtendTo(ALine, ACol: Integer);
begin
  if not FActive then
    Exit;
  FActiveLine := ALine;
  FActiveCol := ACol;
end;

procedure TSelection.Clear;
begin
  FActive := False;
end;

function TSelection.IsEmpty: Boolean;
begin
  Result := (not FActive) or
            ((FAnchorLine = FActiveLine) and (FAnchorCol = FActiveCol));
end;

procedure TSelection.Normalize(out SLine, SCol, ELine, ECol: Integer);
begin
  // Anchor before Active in document order -> already in order.
  if (FAnchorLine < FActiveLine) or
     ((FAnchorLine = FActiveLine) and (FAnchorCol <= FActiveCol)) then
  begin
    SLine := FAnchorLine; SCol := FAnchorCol;
    ELine := FActiveLine; ECol := FActiveCol;
  end
  else
  begin
    SLine := FActiveLine; SCol := FActiveCol;
    ELine := FAnchorLine; ECol := FAnchorCol;
  end;
end;

procedure TSelection.GetRange(out SLine, SCol, ELine, ECol: Integer);
begin
  Normalize(SLine, SCol, ELine, ECol);
end;

function TSelection.RangeOnLine(ALine, ALineLen: Integer;
  out C0, C1: Integer): Boolean;
var
  SLine, SCol, ELine, ECol: Integer;
begin
  Result := False;
  if IsEmpty then
    Exit;

  Normalize(SLine, SCol, ELine, ECol);
  if (ALine < SLine) or (ALine > ELine) then
    Exit;                             // line is entirely outside the selection

  // First selected line starts at SCol; interior/last lines start at 0.
  if ALine = SLine then C0 := SCol else C0 := 0;
  // Last selected line ends at ECol; first/interior lines run to end of line.
  if ALine = ELine then C1 := ECol else C1 := ALineLen;

  // Clamp to the line's character cells.
  if C0 < 0 then C0 := 0;
  if C0 > ALineLen then C0 := ALineLen;
  if C1 > ALineLen then C1 := ALineLen;

  Result := C1 > C0;
end;

end.
