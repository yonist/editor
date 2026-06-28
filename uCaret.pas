unit uCaret;

{$mode delphi}{$H+}

interface

uses
  Classes, Windows, Graphics;

type
  { TCaret
    Tracks the logical caret position (Line, Col, both 0-based) AND owns the
    Win32 system caret. Everything caret-related lives here: creation, showing,
    hiding, positioning and destruction.

    With word wrap, a logical column no longer maps to a screen X by itself, so
    the host control computes the pixel position (it owns the wrap layout) and
    pushes it here via MoveTo. The host still supplies:
      - the window handle + focus transitions (Show / Hide)
      - the caret bar height (SetLineHeight) and colour (SetColor)
      - a chance to hide/show around painting (SuspendForPaint / ResumeAfterPaint)

    A solid-colour bitmap of the caret size is passed to CreateCaret so the
    caret can be coloured (a NULL-bitmap caret is always black - invisible on a
    dark theme).

    See: https://learn.microsoft.com/en-us/windows/win32/menurc/carets }
  TCaret = class
  private
    FLine: Integer;
    FCol: Integer;
    FX: Integer;            // current pixel position
    FY: Integer;
    FHandle: THandle;       // owning window while active
    FActive: Boolean;       // a system caret currently exists on FHandle
    FWidth: Integer;        // caret bar width, px
    FLineHeight: Integer;   // caret bar height, px
    FCaretColor: TColor;    // desired caret colour
    FBackColor: TColor;     // background it sits over (for the XOR shape)
    FBitmap: HBITMAP;       // caret shape (filled with Back XOR Caret)
    FOnChange: TNotifyEvent;
    procedure ApplyPos;
    procedure RebuildBitmap;
    procedure CreateOS;     // (re)create + show the OS caret with the current bitmap
  public
    constructor Create;
    destructor Destroy; override;

    // Logical position (the host maps this to pixels via MoveTo).
    procedure SetPosition(ALine, ACol: Integer);

    // Caret bar height (matches the line height) and colours. The Win32 caret
    // is XOR-drawn, so we fill the shape with (Back XOR Caret): XOR-ing that
    // against the background renders the requested caret colour. (A plain colour
    // fill would be invisible whenever it cancels the background - e.g. black.)
    procedure SetLineHeight(AHeight: Integer);
    procedure SetColors(ACaret, ABack: TColor);

    // Pixel position, computed by the host from the wrap layout.
    procedure MoveTo(AX, AY: Integer);

    // Focus lifecycle: create+show on focus, destroy on blur.
    procedure Show(AHandle: THandle);
    procedure Hide;

    // Paint helpers: the system caret must be hidden while we draw over it.
    procedure SuspendForPaint;
    procedure ResumeAfterPaint;

    property Line: Integer read FLine write FLine;
    property Col: Integer read FCol write FCol;
    property Active: Boolean read FActive;

    // Fired when the logical position is changed via SetPosition, so the host
    // can scroll the new position into view. (Not fired by MoveTo, which is the
    // host pushing a pixel position back down.)
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

constructor TCaret.Create;
begin
  inherited Create;
  FWidth := 2;
  FLineHeight := 1;
  FCaretColor := clBlack;
  FBackColor := clWhite;
  FBitmap := 0;
end;

destructor TCaret.Destroy;
begin
  Hide;
  if FBitmap <> 0 then
    DeleteObject(FBitmap);
  inherited Destroy;
end;

procedure TCaret.RebuildBitmap;
var
  ScreenDC, MemDC: HDC;
  OldBmp: HGDIOBJ;
  Brush: HBRUSH;
  R: Windows.TRect;
begin
  if FBitmap <> 0 then
  begin
    DeleteObject(FBitmap);
    FBitmap := 0;
  end;
  if (FWidth <= 0) or (FLineHeight <= 0) then
    Exit;

  // A small bitmap of the caret size, filled solid with the caret colour.
  ScreenDC := GetDC(0);
  FBitmap := CreateCompatibleBitmap(ScreenDC, FWidth, FLineHeight);
  MemDC := CreateCompatibleDC(ScreenDC);
  OldBmp := SelectObject(MemDC, FBitmap);
  // XOR shape: (background XOR caret) XOR background == caret.
  Brush := CreateSolidBrush(COLORREF(ColorToRGB(FBackColor) xor ColorToRGB(FCaretColor)));
  R.Left := 0; R.Top := 0; R.Right := FWidth; R.Bottom := FLineHeight;
  Windows.FillRect(MemDC, R, Brush);
  DeleteObject(Brush);
  SelectObject(MemDC, OldBmp);
  DeleteDC(MemDC);
  ReleaseDC(0, ScreenDC);
end;

procedure TCaret.CreateOS;
begin
  RebuildBitmap;          // size/colour may have changed since last time
  // With a bitmap, CreateCaret takes the shape from it (the width/height args
  // are ignored, but harmless to pass).
  Windows.CreateCaret(FHandle, FBitmap, FWidth, FLineHeight);
  ApplyPos;
  Windows.ShowCaret(FHandle);
end;

procedure TCaret.SetPosition(ALine, ACol: Integer);
begin
  FLine := ALine;
  FCol := ACol;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TCaret.SetLineHeight(AHeight: Integer);
begin
  if AHeight < 1 then
    AHeight := 1;
  FLineHeight := AHeight;
  if FActive then
    CreateOS;             // recreate so the shape matches the new height
end;

procedure TCaret.SetColors(ACaret, ABack: TColor);
begin
  if (ACaret = FCaretColor) and (ABack = FBackColor) then
    Exit;
  FCaretColor := ACaret;
  FBackColor := ABack;
  if FActive then
    CreateOS;             // recreate so the caret takes the new colour
end;

procedure TCaret.MoveTo(AX, AY: Integer);
begin
  FX := AX;
  FY := AY;
  ApplyPos;
end;

procedure TCaret.Show(AHandle: THandle);
begin
  if FActive and (FHandle = AHandle) then
    Exit;

  FHandle := AHandle;
  FActive := True;
  CreateOS;
end;

procedure TCaret.Hide;
begin
  if not FActive then
    Exit;
  Windows.DestroyCaret;
  FActive := False;
  FHandle := 0;
end;

procedure TCaret.SuspendForPaint;
begin
  if FActive then
    Windows.HideCaret(FHandle);
end;

procedure TCaret.ResumeAfterPaint;
begin
  if FActive then
    Windows.ShowCaret(FHandle);
end;

procedure TCaret.ApplyPos;
begin
  if FActive then
    Windows.SetCaretPos(FX, FY);
end;

end.
