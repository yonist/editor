unit bimburi.textcontrol.scrollcontrol;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types;

type
  { Which scrollbar thumb a mouse drag is riding. }
  TDragAxis = (daNone, daVert, daHorz);

  { TScrollControl
    A TCustomControl that adds mouse-driven scrolling with custom-drawn
    scrollbars, kept independent of whatever content sits on top.

    It owns the scroll position (in pixels), the wheel handling, and the bars
    (geometry, drawing, thumb drag, track paging). It does NOT know what the
    content is: the descendant must push the total content extent
    (ContentHeight / ContentWidth) whenever its layout changes, and read
    ScrollOffsetY / ScrollOffsetX when painting / positioning anything.

    The vertical bar strip on the right is ALWAYS reserved so the content width
    (and thus a descendant's wrap width) is stable regardless of whether the bar
    shows. The horizontal strip at the bottom is reserved only while the content
    actually overflows (ContentWidth > ViewportWidth); this is loop-free because
    ContentWidth never depends on the viewport height. A descendant that never
    wants horizontal scrolling simply pushes ContentWidth = 0.

    Painting uses the template-method pattern: descendants override PaintContent
    (not Paint); the base calls it and then draws the bars on top. }
  TScrollControl = class(TCustomControl)
  private
    FScrollY: Integer;        // vertical scroll offset, px
    FScrollX: Integer;        // horizontal scroll offset, px
    FContentHeight: Integer;  // total virtual content height, px (set by descendant)
    FContentWidth: Integer;   // total virtual content width, px (0 = no horizontal scrolling)
    FScrollStep: Integer;     // px per wheel "line"
    FHScrollStep: Integer;    // px per horizontal wheel "line"
    FBarWidth: Integer;       // thickness of the (reserved) scrollbar strips, px
    FMinThumb: Integer;       // minimum thumb length, px
    FDragAxis: TDragAxis;     // which thumb a drag is riding (daNone = no drag)
    FDragOffset: Integer;     // grab point inside the thumb, px
    FWheelAccum: Integer;     // leftover wheel delta (for sub-notch trackpad scrolling)
    FWheelAccumH: Integer;    // same, for the horizontal axis (Shift+wheel / tilt wheel)
    FTrackColor: TColor;      // scrollbar track
    FThumbColor: TColor;      // scrollbar thumb
    function MaxScrollY: Integer;
    function MaxScrollX: Integer;
    function ThumbRect: TRect;
    function HThumbRect: TRect;
    procedure SetScrollY(AValue: Integer);
    procedure SetScrollX(AValue: Integer);
    procedure SetContentHeight(AValue: Integer);
    procedure SetContentWidth(AValue: Integer);
    // Height of the reserved bottom strip: BarWidth while the content overflows
    // horizontally, else 0. Routing this through ViewportHeight makes all the
    // vertical math (thumb, paging, margins) adapt without further changes.
    function HBarStrip: Integer;
  protected
    procedure Paint; override;
    procedure PaintContent; virtual; abstract;   // descendant draws here
    procedure DrawScrollBar; virtual;            // base draws the bars + corner
    // Theme the scrollbar (called by descendants when a theme is applied).
    procedure SetScrollColors(ATrack, AThumb: TColor);
    procedure Scrolled; virtual;                 // hook: scroll position changed

    function ViewportHeight: Integer;            // visible content height, px (bottom strip excluded)
    function ViewportWidth: Integer;             // visible content width, px (right strip reserved)
    function ScrollBarVisible: Boolean;
    function HScrollBarVisible: Boolean;

    // Scroll the minimum amount so the pixel range [ATop, ABottom) is visible.
    procedure ScrollIntoView(ATop, ABottom: Integer);
    // Horizontal mirror: minimally scroll so [ALeft, ARight) is visible.
    procedure ScrollIntoViewX(ALeft, ARight: Integer);

    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;

    // Writable for descendants that scroll to an absolute position (e.g. page
    // navigation); the setters clamp to the valid range.
    property ScrollOffsetY: Integer read FScrollY write SetScrollY;
    property ScrollOffsetX: Integer read FScrollX write SetScrollX;
    property ContentHeight: Integer read FContentHeight write SetContentHeight;
    property ContentWidth: Integer read FContentWidth write SetContentWidth;
    property ScrollStep: Integer read FScrollStep write FScrollStep;
    property HScrollStep: Integer read FHScrollStep write FHScrollStep;
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
  FHScrollStep := 16;
  FTrackColor := clBtnFace;   // theme overrides these
  FThumbColor := clBtnShadow;
  DoubleBuffered := True;     // flicker-free scroll repaints
end;

procedure TScrollControl.SetScrollColors(ATrack, AThumb: TColor);
begin
  FTrackColor := ATrack;
  FThumbColor := AThumb;
end;

function TScrollControl.HBarStrip: Integer;
begin
  if HScrollBarVisible then
    Result := FBarWidth
  else
    Result := 0;
end;

function TScrollControl.ViewportHeight: Integer;
begin
  Result := ClientHeight - HBarStrip;
  if Result < 0 then
    Result := 0;
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

function TScrollControl.HScrollBarVisible: Boolean;
begin
  // Note: against ViewportWidth (right strip reserved), NOT ClientWidth - and
  // deliberately independent of any height, so reserving the bottom strip can
  // never feed back into this test.
  Result := FContentWidth > ViewportWidth;
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

procedure TScrollControl.SetScrollX(AValue: Integer);
var
  M: Integer;
begin
  M := MaxScrollX;
  if AValue < 0 then
    AValue := 0
  else if AValue > M then
    AValue := M;

  if AValue = FScrollX then
    Exit;

  FScrollX := AValue;
  Scrolled;
  Invalidate;
end;

function TScrollControl.MaxScrollX: Integer;
begin
  Result := FContentWidth - ViewportWidth;
  if Result < 0 then
    Result := 0;
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

procedure TScrollControl.SetContentWidth(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  FContentWidth := AValue;

  // Re-clamp: shrinking the content (or wrap turning on, which pushes 0)
  // snaps the horizontal offset back into range - possibly to 0.
  if FScrollX > MaxScrollX then
    FScrollX := MaxScrollX;

  // The bottom strip may have (dis)appeared, which changes ViewportHeight -
  // re-clamp the vertical offset too.
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

procedure TScrollControl.ScrollIntoViewX(ALeft, ARight: Integer);
begin
  if ALeft < FScrollX then
    SetScrollX(ALeft)                           // range is left of the viewport
  else if ARight > FScrollX + ViewportWidth then
    SetScrollX(ARight - ViewportWidth);         // range is right of the viewport
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

function TScrollControl.HThumbRect: TRect;
var
  Vw, Tw, MaxX, L: Integer;
begin
  Vw := ViewportWidth;
  if (FContentWidth <= Vw) or (FContentWidth <= 0) then
    Exit(Rect(0, 0, 0, 0));

  // Thumb width is proportional to the visible fraction of the content.
  Tw := Integer((Int64(Vw) * Vw) div FContentWidth);
  if Tw < FMinThumb then
    Tw := FMinThumb;
  if Tw > Vw then
    Tw := Vw;

  MaxX := MaxScrollX;
  if MaxX > 0 then
    L := Integer((Int64(FScrollX) * (Vw - Tw)) div MaxX)
  else
    L := 0;

  Result := Rect(L, ViewportHeight, L + Tw, ClientHeight);
end;

procedure TScrollControl.Paint;
begin
  PaintContent;     // descendant draws the content (offset by the scroll offsets)
  DrawScrollBar;    // base draws the bars on top
end;

procedure TScrollControl.DrawScrollBar;
begin
  Canvas.Brush.Style := bsSolid;

  if ScrollBarVisible then
  begin
    // Vertical track (stops above the bottom strip when that is reserved).
    Canvas.Brush.Color := FTrackColor;
    Canvas.FillRect(Rect(ClientWidth - FBarWidth, 0, ClientWidth, ViewportHeight));
    Canvas.Brush.Color := FThumbColor;
    Canvas.FillRect(ThumbRect);
  end;

  if HScrollBarVisible then
  begin
    // Horizontal track along the reserved bottom strip, plus the corner square
    // where the two strips meet (track colour, so the bars read as one frame).
    Canvas.Brush.Color := FTrackColor;
    Canvas.FillRect(Rect(0, ViewportHeight, ViewportWidth, ClientHeight));
    Canvas.FillRect(Rect(ViewportWidth, ViewportHeight, ClientWidth, ClientHeight));
    Canvas.Brush.Color := FThumbColor;
    Canvas.FillRect(HThumbRect);
  end;
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
  if ssShift in Shift then
  begin
    // Shift+wheel scrolls horizontally (wheel up = left). SetScrollX clamps, so
    // this is a no-op when the content doesn't overflow horizontally.
    Inc(FWheelAccumH, WheelDelta);
    Notches := FWheelAccumH div 120;
    FWheelAccumH := FWheelAccumH - Notches * 120;
    if Notches <> 0 then
      SetScrollX(FScrollX - Notches * Lines * FHScrollStep);
  end
  else
  begin
    Inc(FWheelAccum, WheelDelta);
    Notches := FWheelAccum div 120;
    FWheelAccum := FWheelAccum - Notches * 120;
    if Notches <> 0 then
      // Positive WheelDelta scrolls up (toward the top) -> smaller offset.
      SetScrollY(FScrollY - Notches * Lines * FScrollStep);
  end;

  Result := True;
end;

function TScrollControl.DoMouseWheelHorz(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Lines, Notches: Integer;
begin
  // Tilt wheels / trackpad horizontal swipes arrive here (WM_MOUSEHWHEEL).
  Result := inherited DoMouseWheelHorz(Shift, WheelDelta, MousePos);
  if Result then
    Exit;

  Lines := Mouse.WheelScrollLines;
  if Lines <= 0 then
    Lines := 3;

  Inc(FWheelAccumH, WheelDelta);
  Notches := FWheelAccumH div 120;
  FWheelAccumH := FWheelAccumH - Notches * 120;
  if Notches <> 0 then
    // Positive delta tilts right -> larger offset.
    SetScrollX(FScrollX + Notches * Lines * FHScrollStep);

  Result := True;
end;

procedure TScrollControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Tr: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;

  // The Y guard keeps a click on the corner square from riding the vertical bar.
  if ScrollBarVisible and (X >= ClientWidth - FBarWidth) and (Y < ViewportHeight) then
  begin
    Tr := ThumbRect;
    if (Y >= Tr.Top) and (Y < Tr.Bottom) then
    begin
      // Grab the thumb.
      FDragAxis := daVert;
      FDragOffset := Y - Tr.Top;
    end
    else if Y < Tr.Top then
      SetScrollY(FScrollY - ViewportHeight)   // page up
    else
      SetScrollY(FScrollY + ViewportHeight);  // page down
  end
  else if HScrollBarVisible and (Y >= ViewportHeight) and (X < ViewportWidth) then
  begin
    Tr := HThumbRect;
    if (X >= Tr.Left) and (X < Tr.Right) then
    begin
      FDragAxis := daHorz;
      FDragOffset := X - Tr.Left;
    end
    else if X < Tr.Left then
      SetScrollX(FScrollX - ViewportWidth)    // page left
    else
      SetScrollX(FScrollX + ViewportWidth);   // page right
  end;
end;

procedure TScrollControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Vh, Vw, Th, Tw, NewTop, NewLeft: Integer;
  Tr: TRect;
begin
  inherited MouseMove(Shift, X, Y);

  case FDragAxis of
    daVert:
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
    daHorz:
      begin
        Vw := ViewportWidth;
        Tr := HThumbRect;
        Tw := Tr.Right - Tr.Left;
        NewLeft := X - FDragOffset;
        if Vw - Tw > 0 then
          SetScrollX(Integer((Int64(NewLeft) * MaxScrollX) div (Vw - Tw)))
        else
          SetScrollX(0);
      end;
  end;
end;

procedure TScrollControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragAxis := daNone;
end;

end.
