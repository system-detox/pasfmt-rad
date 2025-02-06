﻿unit Pasfmt.FormatEditor;

interface

uses ToolsAPI, Pasfmt.FormatCore;

type
  TEditViewFormatter = record
    Formatter: TFormatter;

    procedure Format(Buffer: IOTAEditBuffer);
  end;

implementation

uses System.SysUtils, System.Classes, Winapi.Windows, Winapi.ActiveX, Vcl.AxCtrls;

//______________________________________________________________________________________________________________________

function StreamToUTF8(Stream: IStream): UTF8String;
var
  OleStream: TOleStream;
begin
  OleStream := TOleStream.Create(Stream);
  try
    SetLength(Result, OleStream.Size);
    OleStream.Seek(0, soBeginning);
    if OleStream.Read(Result[1], Length(Result)) <> OleStream.Size then
      raise Exception.Create('The stream could not be read');
  finally
    FreeAndNil(OleStream);
  end;
end;

//______________________________________________________________________________________________________________________

procedure TrimTrailingNewlines(Data: PAnsiChar; Length: Integer);
var
  StrEnd: PAnsiChar;
begin
  StrEnd := Data + Length;
  while (StrEnd > Data) and ((StrEnd - 1)^ in [#$0A, #$0D]) do
    Dec(StrEnd);
  StrEnd^ := #0;
end;

//______________________________________________________________________________________________________________________

function GetBufferViewCursors(Buffer: IOTAEditBuffer): TArray<Integer>;
var
  I: Integer;
  EditView: IOTAEditView;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
begin
  SetLength(Result, Buffer.EditViewCount);
  for I := 0 to Buffer.EditViewCount - 1 do begin
    EditView := Buffer.EditViews[I];

    EditPos := EditView.CursorPos;
    EditView.ConvertPos(True, EditPos, CharPos);
    Result[I] := EditView.CharPosToPos(CharPos);
  end;
end;

//______________________________________________________________________________________________________________________

procedure SetBufferViewCursors(Buffer: IOTAEditBuffer; Cursors: TArray<Integer>);
var
  I: Integer;
  EditView: IOTAEditView;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
begin
  for I := 0 to Buffer.EditViewCount - 1 do begin
    if (I >= Length(Cursors)) or (Cursors[I] < 0) then begin
      Continue;
    end;

    EditView := Buffer.EditViews[I];

    CharPos := EditView.PosToCharPos(Cursors[I]);
    EditView.ConvertPos(False, EditPos, CharPos);
    EditView.CursorPos := EditPos;
    EditView.Paint;
  end;
end;

//______________________________________________________________________________________________________________________

procedure TEditViewFormatter.Format(Buffer: IOTAEditBuffer);
var
  SourceEditor: IOTAEditorContent;
  EditorContent: UTF8String;
  FormatResult: TFormatResult;
  Writer: IOTAEditWriter;
begin
  if Buffer.QueryInterface(IOTAEditorContent, SourceEditor) = S_OK then begin
    EditorContent := StreamToUTF8(SourceEditor.Content);
  end
  else begin
    raise Exception.Create('Editor doesn''t support IOTAEditorContent');
  end;

  FormatResult := Formatter.Format(EditorContent, GetBufferViewCursors(Buffer));
  Assert(FormatResult.ExitCode = 0);

  Writer := Buffer.CreateUndoableWriter;
  Writer.DeleteTo(MaxInt);
  // the IDE always inserts a line ending after whatever we insert, so we have to trim the trailing line ending
  // that pasfmt creates.
  TrimTrailingNewlines(PAnsiChar(FormatResult.Output), Length(FormatResult.Output));
  // While it would possible to insert with this Writer incrementally as stdout is consumed from the subprocess
  // (avoiding collecting the entire output into a string), using this method from a thread other than the main thread
  // either hangs or breaks things. I think this is the fault of the VCL components.
  // Also, if you call this method more than once than the scroll position of the editor is ruined.
  Writer.Insert(PAnsiChar(FormatResult.Output));

  SetBufferViewCursors(Buffer, FormatResult.Cursors);
end;

//______________________________________________________________________________________________________________________

end.
