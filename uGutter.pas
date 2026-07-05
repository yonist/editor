unit uGutter;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Types, Graphics, uLayout;

type
  { TGutter
    The left-hand strip that shows line numbers. A passive helper (like TLayout
    and TCaret): it owns all of the gutter's state - its width, colours, padding
    and drawing - but never triggers relayout or repaint itself. The host control
    feeds it the line count + metrics (Recalc) and the canvas + visible rows
    (Draw), and decides when those happen.

    Width is cached and only depends on the line count (digits) and cell width,
    so there is no gutter<->layout feedback loop: the host calls Recalc before it
    computes the wrap width, and reads Width to offset the text origin. }
  TGutter = class
  private
    FVisible: Boolean;
    FWidth: Integer;          // cached strip width, px (0 when hidden)
    FCharWidth: Integer;      // cached at Recalc, used to right-align numbers
    FBackColor: TColor;
    FForeColor: TColor;
    FSeparatorColor: TColor;
    FMinDigits: Integer;      // floor on digit count so the width doesn't jitter
    FLeftPad: Integer;        // px inset on the left of the strip
    FRightPad: Integer;       // px inset between the number and the separator
    FInterval: Integer;       // print the number every Nth line; dots in between (1 = every line)
    function DigitCount(AValue: Integer): Integer;
  public
    constructor Create;

    // Themed colours (called by the host when a theme is applied).
    procedure SetColors(ABack, AFore, ASeparator: TColor);

    // Recompute the cached width from the current line count and cell width.
    // Sets Width to 0 while hidden (so the host's text origin collapses to just
    // its left margin - i.e. no gutter).
    procedure Recalc(ALineCount, ACharWidth: Integer);

    // Paint the strip: background, separator, and the line numbers for the
    // visible visual rows [AFirst..ALast]. Only the first visual row of each
    // logical line (StartCol = 0) gets a number; wrapped continuation rows are
    // left blank.
    procedure Draw(ACanvas: TCanvas; ALayout: TLayout;
      AFirst, ALast, ALineHeight, AScrollOffsetY, AClientHeight: Integer);

    property Visible: Boolean read FVisible write FVisible;
    property Width: Integer read FWidth;
    // Print the actual number only on every Nth line; other lines get a centered
    // placeholder dot. 1 (the default) prints every line number.
    property Interval: Integer read FInterval write FInterval;
  end;

implementation

constructor TGutter.Create;
begin
  inherited Create;
  FVisible := False;      // off by default; TCodeEditor turns it on
  FMinDigits := 4;
  FLeftPad := 6;
  FRightPad := 12;   // gap between the number and the separator line
  FInterval := 5;    // every line numbered by default
end;

procedure TGutter.SetColors(ABack, AFore, ASeparator: TColor);
begin
  FBackColor := ABack;
  FForeColor := AFore;
  FSeparatorColor := ASeparator;
end;

function TGutter.DigitCount(AValue: Integer): Integer;
begin
  if AValue < 0 then
    AValue := 0;
  Result := 1;
  while AValue >= 10 do
  begin
    AValue := AValue div 10;
    Inc(Result);
  end;
end;

procedure TGutter.Recalc(ALineCount, ACharWidth: Integer);
var
  Digits: Integer;
begin
  FCharWidth := ACharWidth;
  if (not FVisible) or (ACharWidth <= 0) then
  begin
    FWidth := 0;                       // hidden -> the host text origin has no gutter
    Exit;
  end;
  Digits := DigitCount(ALineCount);    // digits in the largest (1-based) line number
  if Digits < FMinDigits then
    Digits := FMinDigits;
  FWidth := Digits * ACharWidth + FLeftPad + FRightPad;
end;

procedure TGutter.Draw(ACanvas: TCanvas; ALayout: TLayout;
  AFirst, ALast, ALineHeight, AScrollOffsetY, AClientHeight: Integer);
const
  DotChar = #$C2#$B7;                  // U+00B7 MIDDLE DOT, UTF-8 encoded
var
  i, Yp, LineNo: Integer;
  Row: TVisualRow;
  S: string;
begin
  if (not FVisible) or (FWidth <= 0) then
    Exit;

  // Strip background (covers the full client height so it reads as a column).
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := FBackColor;
  ACanvas.FillRect(Rect(0, 0, FWidth, AClientHeight));

  // Separator on the gutter/text boundary.
  ACanvas.Pen.Color := FSeparatorColor;
  ACanvas.Line(FWidth - 1, 0, FWidth - 1, AClientHeight);

  // Line numbers, right-aligned within the strip. Numbers use the canvas font,
  // which the host has already set to its monospace face.
  ACanvas.Brush.Style := bsClear;      // don't paint a box behind the digits
  ACanvas.Font.Color := FForeColor;
  for i := AFirst to ALast do
  begin
    Row := ALayout[i];
    if Row.StartCol <> 0 then
      Continue;                        // wrapped continuation row -> no number
    LineNo := Row.LogicalLine + 1;     // line numbers are 1-based
    Yp := i * ALineHeight - AScrollOffsetY;
    if ((FInterval > 1) and (LineNo mod FInterval <> 0)) and (LineNo <> 1) then
      // Off-interval line: a centered placeholder dot instead of the number.
      ACanvas.TextOut(
        FLeftPad + ((FWidth - FLeftPad - FRightPad) - FCharWidth) div 2, Yp, DotChar)
    else
    begin
      // Number, right-aligned against the separator gap.
      S := IntToStr(LineNo);
      ACanvas.TextOut(FWidth - FRightPad - System.Length(S) * FCharWidth, Yp, S);
    end;
  end;
end;

end.
