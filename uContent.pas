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

    // Raw text serialization (UTF-8, no BOM; a UTF-8 BOM is stripped on load).
    procedure SaveToStream(AStream: TStream);
    procedure LoadFromStream(AStream: TStream);

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

procedure TContent.SaveToStream(AStream: TStream);
var
  S: string;
begin
  // LCL strings are UTF-8, so the bytes of Text are already UTF-8. No BOM.
  S := FLines.Text;
  if Length(S) > 0 then
    AStream.WriteBuffer(S[1], Length(S));
end;

procedure TContent.LoadFromStream(AStream: TStream);
var
  S: string;
  N: Integer;
begin
  N := AStream.Size - AStream.Position;
  if N < 0 then
    N := 0;
  SetLength(S, N);
  if N > 0 then
    AStream.ReadBuffer(S[1], N);

  // Strip a leading UTF-8 BOM (EF BB BF) if present.
  if (Length(S) >= 3) and (S[1] = #$EF) and (S[2] = #$BB) and (S[3] = #$BF) then
    System.Delete(S, 1, 3);

  FLines.Text := S;            // parses CR / LF / CRLF line endings
  if FLines.Count = 0 then
    FLines.Add('');            // keep the never-empty invariant
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
