unit uCodeEditor;

{$mode delphi}{$H+}

interface

uses
  Classes, uTextControl;

type
  { TCodeEditor
    A code editor control. For now it adds nothing on top of TTextControl:
    it simply prints its content to the client area. }
  TCodeEditor = class(TTextControl)
  end;

implementation

end.
