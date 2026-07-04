unit uConsoleSpinner;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, ExtCtrls;

type
  TConsoleSpinnerType = (csDots, csDots4, csPipes, csClock); // the look of the spinner

  { TConsoleSpinner
    A self-contained animated spinner. It knows nothing about the console; it
    just calls back a writer on a timer. The first tick appends a line, every
    later tick rewrites that same line (rewriteLine = True). }
  TConsoleSpinner = class sealed
  type
    TWriteCallback =
      procedure(const AText: unicodestring; const rewriteLine: boolean = False) of object;
  private
    FActive: boolean;
    FTimer: TTimer;
    FWriteCallback: TWriteCallback;
    FSpinnerChars: array of unicodestring;
    FFirstChar: boolean;
    FCounter: integer;
  protected
    procedure WriteSpinner(Sender: TObject);
  public
    constructor Create(const aWriteCallback: TWriteCallback);
    destructor Destroy(); override;
    property IsActive: boolean read FActive;
    procedure Start(const aSpinnerType: TConsoleSpinnerType = csClock);
    procedure Stop();
  end;

implementation

procedure TConsoleSpinner.WriteSpinner(Sender: TObject);
begin
  if FFirstChar then
  begin
    FWriteCallback(FSpinnerChars[FCounter], False);
    FFirstChar := False;
  end
  else
  begin
    FWriteCallback(FSpinnerChars[FCounter], True);
  end;

  Inc(FCounter);
  if FCounter = length(FSpinnerChars) then
    FCounter := 0;
end;

constructor TConsoleSpinner.Create(const aWriteCallback: TWriteCallback);
begin
  FActive := False;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  // The default is true for some reason.. so it cause all sorts of problems
  FTimer.OnTimer := WriteSpinner;
  FTimer.Interval := 100;

  if not Assigned(aWriteCallback) then
    raise Exception.Create('You must a valid write callback function');
  FWriteCallback := aWriteCallback;
end;

destructor TConsoleSpinner.Destroy();
begin
  FreeAndNil(FTimer);
  inherited;
end;

procedure TConsoleSpinner.Start(const aSpinnerType: TConsoleSpinnerType);
begin
  FActive := True;
  FFirstChar := True;
  FCounter := 0;

  case aSpinnerType of
    csDots: FSpinnerChars :=
        ['⠈', '⠉', '⠋', '⠓', '⠒', '⠐', '⠐', '⠒', '⠖', '⠦', '⠤',
        '⠠', '⠠', '⠤', '⠦', '⠖', '⠒', '⠐', '⠐', '⠒', '⠓', '⠋', '⠉', '⠈'];
    csDots4: FSpinnerChars :=
        ['⠄', '⠆', '⠇', '⠋', '⠙', '⠸', '⠰', '⠠', '⠰', '⠸', '⠙', '⠋', '⠇', '⠆'];
    csPipes: FSpinnerChars := ['┤', '┘', '┴', '└', '├', '┌', '┬', '┐'];
    csClock: FSpinnerChars :=
        [UnicodeString(#$1F550), UnicodeString(#$1F551), UnicodeString(#$1F552),
         UnicodeString(#$1F553), UnicodeString(#$1F554), UnicodeString(#$1F555),
         UnicodeString(#$1F556), UnicodeString(#$1F557), UnicodeString(#$1F558),
         UnicodeString(#$1F559), UnicodeString(#$1F55A), UnicodeString(#$1F55B)
         ];
  end;
  FTimer.Enabled := True;
end;

procedure TConsoleSpinner.Stop();
begin
  FTimer.Enabled := False;
  FActive := False;
end;

end.
