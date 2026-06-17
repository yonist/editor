unit uContent;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils;

type
  { TContent
    Holds the text of a text control. The text itself lives in a TStringList,
    but it is wrapped here so the controls never touch the TStringList directly. }
  TContent = class
  private
    FLines: TStringList;
    function GetCount: Integer;
    function GetLine(AIndex: Integer): string;
    procedure SetLine(AIndex: Integer; const AValue: string);
    function GetText: string;
    procedure SetText(const AValue: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Add(const ALine: string): Integer;
    procedure Insert(AIndex: Integer; const ALine: string);
    procedure Delete(AIndex: Integer);

    property Count: Integer read GetCount;
    property Lines[AIndex: Integer]: string read GetLine write SetLine; default;
    property Text: string read GetText write SetText;
  end;

implementation

constructor TContent.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FLines.Add(''); // Ensures that the content is never empty
end;

destructor TContent.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TContent.Clear;
begin
  FLines.Clear;
end;

function TContent.Add(const ALine: string): Integer;
begin
  Result := FLines.Add(ALine);
end;

procedure TContent.Insert(AIndex: Integer; const ALine: string);
begin
  FLines.Insert(AIndex, ALine);
end;

procedure TContent.Delete(AIndex: Integer);
begin
  FLines.Delete(AIndex);
  if FLines.Count = 0 then
     FLines.Add(''); // Ensures that the content is never empty
end;

function TContent.GetCount: Integer;
begin
  Result := FLines.Count;
end;

function TContent.GetLine(AIndex: Integer): string;
begin
  Result := FLines[AIndex];
end;

procedure TContent.SetLine(AIndex: Integer; const AValue: string);
begin
  FLines[AIndex] := AValue;
end;

function TContent.GetText: string;
begin
  Result := FLines.Text;
end;

procedure TContent.SetText(const AValue: string);
begin
  FLines.Text := AValue;
end;

end.
