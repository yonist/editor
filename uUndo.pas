unit uUndo;

{$mode delphi}{$H+}

interface

uses
  Types;

type
  TUndoLines = array of string;

  { TUndoSel
    A selection snapshot in content coordinates (ordered range, X=col, Y=line).
    HasSel = False means "no selection / caret only". }
  TUndoSel = record
    HasSel: Boolean;
    SelStart: TPoint;
    SelEnd: TPoint;
  end;

  { TUndoRecord
    One line-block edit, stored lazily. It keeps only the block needed to
    restore when the record is applied (Lines) plus the count of the block
    currently in the content (OtherCount) - the opposite side is read back
    from the live content at apply-time (safe because undo/redo is strict LIFO).
    Caret and selection each come in a Target/Other pair: Target is restored
    when this record is applied; Other is for its inverse. Both pairs swap when
    the record flips between the undo and redo stacks. }
  TUndoRecord = record
    FirstLine: Integer;
    Lines: TUndoLines;
    OtherCount: Integer;
    CaretTarget: TPoint;
    CaretOther: TPoint;
    SelTarget: TUndoSel;
    SelOther: TUndoSel;
  end;

  TUndoRecordArray = array of TUndoRecord;

const
  UndoMaxDepth = 20;   // fixed capacity; the array is allocated once

type
  { TUndoManager
    A single linear history with a cursor (no separate redo stack):
      FHistory : the timeline, allocated once at UndoMaxDepth (never resized).
      FCount   : number of live records.
      FCursor  : split point - records [0, FCursor) are undoable, [FCursor,
                 FCount) are redoable.

    Pure storage: the host owns the content and computes a record's inverse
    (TTextControl.ApplyRecord). Undo/Redo use a Peek + Commit pair: the host
    peeks the boundary record, applies it (which yields the inverse), and
    commits the inverse back into the same slot - so the boundary record flips
    in place between its undo and redo forms as the cursor crosses it. }
  TUndoManager = class
  private
    FHistory: TUndoRecordArray;
    FCount: Integer;
    FCursor: Integer;
  public
    constructor Create;

    // A fresh user edit: drops the redo branch, then appends (shifting out the
    // oldest record if the array is full).
    procedure RecordEdit(const ARec: TUndoRecord);

    // Undo: PeekUndo the boundary record, then CommitUndo its inverse.
    function PeekUndo(out ARec: TUndoRecord): Boolean;
    procedure CommitUndo(const AInverse: TUndoRecord);
    // Redo: PeekRedo the boundary record, then CommitRedo its inverse.
    function PeekRedo(out ARec: TUndoRecord): Boolean;
    procedure CommitRedo(const AInverse: TUndoRecord);

    procedure Clear;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
  end;

implementation

constructor TUndoManager.Create;
begin
  inherited Create;
  SetLength(FHistory, UndoMaxDepth);   // one allocation for the lifetime
  FCount := 0;
  FCursor := 0;
end;

procedure TUndoManager.RecordEdit(const ARec: TUndoRecord);
var
  i: Integer;
begin
  // 1. Drop the redo branch (records at/after the cursor) and free their data.
  for i := FCursor to FCount - 1 do
    FHistory[i] := Default(TUndoRecord);
  FCount := FCursor;

  // 2. If the array is full (no redo branch was dropped), shift out the oldest.
  if FCount = UndoMaxDepth then
  begin
    {
       This is the slow naive algo
       for i := 1 to FCount - 1 do
         FHistory[i - 1] := FHistory[i];

       FHistory[FCount - 1] := Default(TUndoRecord);   // nil the freed tail slot


       if it ever gets to slow switch to ring buffer so no shift is ever needed
    }
    FHistory[0] := Default(TUndoRecord);                          // finalize oldest (frees it)
    Move(FHistory[1], FHistory[0], (FCount-1)*SizeOf(TUndoRecord));
    FillChar(FHistory[FCount-1], SizeOf(TUndoRecord), 0);  // blank tail, NO finalize
    Dec(FCount);
    Dec(FCursor);
  end;

  // 3. Append.
  FHistory[FCount] := ARec;
  Inc(FCount);
  FCursor := FCount;
end;

function TUndoManager.PeekUndo(out ARec: TUndoRecord): Boolean;
begin
  Result := FCursor > 0;
  if Result then
    ARec := FHistory[FCursor - 1];
end;

procedure TUndoManager.CommitUndo(const AInverse: TUndoRecord);
begin
  // Flip the boundary record to its redo form in place; the cursor steps back
  // so that slot is now the head of the redo branch.
  FHistory[FCursor - 1] := AInverse;
  Dec(FCursor);
end;

function TUndoManager.PeekRedo(out ARec: TUndoRecord): Boolean;
begin
  Result := FCursor < FCount;
  if Result then
    ARec := FHistory[FCursor];
end;

procedure TUndoManager.CommitRedo(const AInverse: TUndoRecord);
begin
  FHistory[FCursor] := AInverse;
  Inc(FCursor);
end;

procedure TUndoManager.Clear;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    FHistory[i] := Default(TUndoRecord);   // free line arrays
  FCount := 0;
  FCursor := 0;
end;

function TUndoManager.CanUndo: Boolean;
begin
  Result := FCursor > 0;
end;

function TUndoManager.CanRedo: Boolean;
begin
  Result := FCursor < FCount;
end;

end.
