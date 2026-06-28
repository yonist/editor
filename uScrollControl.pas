unit uScrollControl;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types;

type
  { TScrollControl
    A TCustomControl that adds mouse-driven vertical scrolling with a
    custom-drawn scrollbar, kept independent of whatever content sits on top.

    It owns the scroll position (in pixels), the wheel handling, and the bar
    (geometry, drawing, thumb drag, track paging). It does NOT know what the
    content is: the descendant must push the total content height
    (ContentHeight) whenever its layout changes, and read ScrollOffsetY when
    painting / positioning anything.

    Painting uses the template-method pattern: descendants override PaintContent
    (not Paint); the base calls it and then draws the bar on top. }
  TScrollControl = class(TCustomControl)
  private
    FScrollY: Integer;        // vertical scroll offset, px
    FContentHeight: Integer;  // total virtual content height, px (set by descendant)
    FScrollStep: Integer;     // px per wheel "line"
    FBarWidth: Integer;       // width of the (reserved) scrollbar strip, px
    FMinThumb: Integer;       // minimum thumb height, px
    FDragging: Boolean;       // a thumb drag is in progress
    FDragOffset: Integer;     // grab point inside the thumb, px
    FWheelAccum: Integer;     // leftover wheel delta (for sub-notch trackpad scrolling)
    FTrackColor: TColor;      // scrollbar track
    FThumbColor: TColor;      // scrollbar thumb
    function MaxScrollY: Integer;
    function ThumbRect: TRect;
    procedure SetScrollY(AValue: Integer);
    procedure SetContentHeight(AValue: Integer);
  protected
    procedure Paint; override;
    procedure PaintContent; virtual; abstract;   // descendant draws here
    procedure DrawScrollBar; virtual;            // base draws the thumb
    // Theme the scrollbar (called by descendants when a theme is applied).
    procedure SetScrollColors(ATrack, AThumb: TColor);
    procedure Scrolled; virtual;                 // hook: scroll position changed

    function ViewportHeight: Integer;            // visible content height, px
    function ViewportWidth: Integer;             // visible content width, px (bar reserved)
    function ScrollBarVisible: Boolean;

    // Scroll the minimum amount so the pixel range [ATop, ABottom) is visible.
    procedure ScrollIntoView(ATop, ABottom: Integer);

    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;

    property ScrollOffsetY: Integer read FScrollY;
    property ContentHeight: Integer read FContentHeight write SetContentHeight;
    property ScrollStep: Integer read FScrollStep write FScrollStep;
    property BarWidth: Integer read FBarWidth;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

constructor TScrollControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBarWidth := 16;
  FMinThumb := 20;
  FScrollStep := 16;
  FTrackColor := clBtnFace;   // theme overrides these
  FThumbColor := clBtnShadow;
  DoubleBuffered := True;     // flicker-free scroll repaints
end;

procedure TScrollControl.SetScrollColors(ATrack, AThumb: TColor);
begin
  FTrackColor := ATrack;
  FThumbColor := AThumb;
end;

function TScrollControl.ViewportHeight: Integer;
begin
  Result := ClientHeight;
end;

function TScrollControl.ViewportWidth: Integer;
begin
  // The bar strip is always reserved so the content width (and thus a
  // descendant's wrap width) is stable regardless of whether the bar shows -
  // this avoids the visibility<->width<->content feedback loop.
  Result := ClientWidth - FBarWidth;
  if Result < 0 then
    Result := 0;
end;

function TScrollControl.MaxScrollY: Integer;
begin
  Result := FContentHeight - ViewportHeight;
  if Result < 0 then
    Result := 0;
end;

function TScrollControl.ScrollBarVisible: Boolean;
begin
  Result := FContentHeight > ViewportHeight;
end;

procedure TScrollControl.SetScrollY(AValue: Integer);
var
  M: Integer;
begin
  M := MaxScrollY;
  if AValue < 0 then
    AValue := 0
  else if AValue > M then
    AValue := M;

  if AValue = FScrollY then
    Exit;

  FScrollY := AValue;
  Scrolled;
  Invalidate;
end;

procedure TScrollControl.SetContentHeight(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  FContentHeight := AValue;

  // Re-clamp the scroll position against the new range.
  if FScrollY > MaxScrollY then
    FScrollY := MaxScrollY;

  Invalidate;
end;

procedure TScrollControl.Scrolled;
begin
  // Hook for descendants (e.g. to reposition a caret). Nothing by default.
end;

procedure TScrollControl.ScrollIntoView(ATop, ABottom: Integer);
begin
  if ATop < FScrollY then
    SetScrollY(ATop)                            // range is above the viewport
  else if ABottom > FScrollY + ViewportHeight then
    SetScrollY(ABottom - ViewportHeight);       // range is below the viewport
end;

function TScrollControl.ThumbRect: TRect;
var
  Vh, Th, MaxY, Top: Integer;
begin
  Vh := ViewportHeight;
  if (FContentHeight <= Vh) or (FContentHeight <= 0) then
    Exit(Rect(0, 0, 0, 0));

  // Thumb height is proportional to the visible fraction of the content.
  Th := Integer((Int64(Vh) * Vh) div FContentHeight);
  if Th < FMinThumb then
    Th := FMinThumb;
  if Th > Vh then
    Th := Vh;

  MaxY := MaxScrollY;
  if MaxY > 0 then
    Top := Integer((Int64(FScrollY) * (Vh - Th)) div MaxY)
  else
    Top := 0;

  Result := Rect(ClientWidth - FBarWidth, Top, ClientWidth, Top + Th);
end;

procedure TScrollControl.Paint;
begin
  PaintContent;     // descendant draws the content (offset by ScrollOffsetY)
  DrawScrollBar;    // base draws the bar on top
end;

procedure TScrollControl.DrawScrollBar;
var
  Tr: TRect;
begin
  if not ScrollBarVisible then
    Exit;

  // Track.
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FTrackColor;
  Canvas.FillRect(Rect(ClientWidth - FBarWidth, 0, ClientWidth, ViewportHeight));

  // Thumb.
  Tr := ThumbRect;
  Canvas.Brush.Color := FThumbColor;
  Canvas.FillRect(Tr);
end;

function TScrollControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Lines, Notches: Integer;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then
    Exit;

  Lines := Mouse.WheelScrollLines;
  if Lines <= 0 then
    Lines := 3;

  // A detented wheel sends multiples of 120; a precision trackpad sends smaller
  // sub-notch deltas. Accumulate them so many small deltas add up to a step
  // instead of each truncating to zero, and keep the remainder for next time.
  Inc(FWheelAccum, WheelDelta);
  Notches := FWheelAccum div 120;
  FWheelAccum := FWheelAccum - Notches * 120;

  if Notches <> 0 then
    // Positive WheelDelta scrolls up (toward the top) -> smaller offset.
    SetScrollY(FScrollY - Notches * Lines * FScrollStep);

  Result := True;
end;

procedure TScrollControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Tr: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);

  if (Button = mbLeft) and ScrollBarVisible and (X >= ClientWidth - FBarWidth) then
  begin
    Tr := ThumbRect;
    if (Y >= Tr.Top) and (Y < Tr.Bottom) then
    begin
      // Grab the thumb.
      FDragging := True;
      FDragOffset := Y - Tr.Top;
    end
    else if Y < Tr.Top then
      SetScrollY(FScrollY - ViewportHeight)   // page up
    else
      SetScrollY(FScrollY + ViewportHeight);  // page down
  end;
end;

procedure TScrollControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Vh, Th, NewTop: Integer;
  Tr: TRect;
begin
  inherited MouseMove(Shift, X, Y);

  if FDragging then
  begin
    Vh := ViewportHeight;
    Tr := ThumbRect;
    Th := Tr.Bottom - Tr.Top;
    NewTop := Y - FDragOffset;
    if Vh - Th > 0 then
      SetScrollY(Integer((Int64(NewTop) * MaxScrollY) div (Vh - Th)))
    else
      SetScrollY(0);
  end;
end;

procedure TScrollControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

end.
