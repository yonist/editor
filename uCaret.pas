unit uCaret;

{$mode delphi}{$H+}

interface

uses
  Classes, Windows;

type
  { TCaret
    Tracks the logical caret position (Line, Col, both 0-based) AND owns the
    Win32 system caret. Everything caret-related lives here: creation, showing,
    hiding, positioning and destruction.

    With word wrap, a logical column no longer maps to a screen X by itself, so
    the host control computes the pixel position (it owns the wrap layout) and
    pushes it here via MoveTo. The host still supplies:
      - the window handle + focus transitions (Show / Hide)
      - the caret bar height (SetLineHeight)
      - a chance to hide/show around painting (SuspendForPaint / ResumeAfterPaint)

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
    FOnChange: TNotifyEvent;
    procedure ApplyPos;
  public
    constructor Create;
    destructor Destroy; override;

    // Logical position (the host maps this to pixels via MoveTo).
    procedure SetPosition(ALine, ACol: Integer);

    // Caret bar height (matches the line height).
    procedure SetLineHeight(AHeight: Integer);

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
end;

destructor TCaret.Destroy;
begin
  Hide;
  inherited Destroy;
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

  // If the caret already exists, recreate it so its height matches.
  // (CreateCaret replaces any existing caret for this thread.)
  if FActive then
  begin
    Windows.CreateCaret(FHandle, 0, FWidth, FLineHeight);
    ApplyPos;
    Windows.ShowCaret(FHandle);
  end;
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
  Windows.CreateCaret(FHandle, 0, FWidth, FLineHeight);
  FActive := True;
  ApplyPos;
  Windows.ShowCaret(FHandle);
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
