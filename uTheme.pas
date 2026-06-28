unit uTheme;

{$mode delphi}{$H+}

interface

uses
  Graphics, uHighlighter;

type
  TThemeKind = (thLight, thDark);

  { TTheme - the full colour palette of a text control. Syntax[tkText] doubles
    as the default foreground. All values are explicit RGB (not OS system
    colours) so a theme looks the same regardless of the desktop theme. }
  TTheme = record
    Background:  TColor;
    SelBack:     TColor;        // selection band
    SelFore:     TColor;        // selected text (single colour)
    Caret:       TColor;
    ScrollTrack: TColor;
    ScrollThumb: TColor;
    Syntax:      TSyntaxColors;
  end;

const
  LightTheme: TTheme = (
    Background:  clWhite;
    SelBack:     $00D77800;     // RGB(0,120,215)
    SelFore:     clWhite;
    Caret:       clBlack;
    ScrollTrack: $00F0F0F0;     // RGB(240,240,240)
    ScrollThumb: $00CDCDCD;     // RGB(205,205,205)
    Syntax: (
      clBlack,   // tkText
      clBlue,    // tkKeyword
      clBlack,   // tkIdentifier
      clGreen,   // tkString
      clGray,    // tkComment
      clTeal,    // tkNumber
      clBlack    // tkOperator
    )
  );

  DarkTheme: TTheme = (
    Background:  $001E1E1E;     // RGB(30,30,30)
    SelBack:     $00784F26;     // RGB(38,79,120)
    SelFore:     clWhite;
    Caret:       $00DCDCDC;     // RGB(220,220,220)
    ScrollTrack: $002D2D2D;     // RGB(45,45,45)
    ScrollThumb: $00505050;     // RGB(80,80,80)
    Syntax: (
      $00D4D4D4, // tkText        RGB(212,212,212)
      $00D69C56, // tkKeyword     RGB(86,156,214)
      $00D4D4D4, // tkIdentifier
      $007891CE, // tkString      RGB(206,145,120)
      $0055996A, // tkComment     RGB(106,153,85)
      $00A8CEB5, // tkNumber      RGB(181,206,168)
      $00D4D4D4  // tkOperator
    )
  );

implementation

end.
