unit uCodeEditor;

{$mode delphi}{$H+}

interface

uses
  Classes, uTextControl;

type
  { TCodeEditor
    A code editor control. On top of TTextControl it shows the line-number
    gutter by default. }
  TCodeEditor = class(TTextControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

constructor TCodeEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ShowGutter := True;
end;

end.
