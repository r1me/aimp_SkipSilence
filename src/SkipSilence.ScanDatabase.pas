unit SkipSilence.ScanDatabase;

{
MIT License

Copyright (c) 2018 aimp_SkipSilence, Damian Woroch, http://rime.ddns.net

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom
the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, System.DateUtils, System.Generics.Collections,
  Xml.XMLDom, Xml.XMLIntf, Xml.XMLDoc;

type
  TAudioScanData = class
    FileName: String;
    Intro, Outro: Int64;
    IntroTime, OutroTime: Double;
    NormalizationGain: Single;
    Duration: Double;
    DateTimeAdded: TDateTime;
  end;

type
  TScanDatabase = class
  private
    FItems: TObjectList<TAudioScanData>;
    FFileName: String;
    procedure CleanupDb;
  public
    property Items: TObjectList<TAudioScanData> read FItems write FItems;

    procedure Add(AudioScanData: TAudioScanData);
    procedure Remove(AItem: TAudioScanData);
    function Find(AudioFileName: String; var AItem: TAudioScanData): Boolean;
    function FindIndex(AudioFileName: String; var AItem: TAudioScanData): Boolean;

    procedure LoadFromFile;
    procedure SaveToFile;

    constructor Create(AFileName: String);
    destructor Destroy; override;
  end;

const
  MAX_DB_ITEMS = 1000;
  DB_FILE_NAME = 'scandb.xml';
  DB_PATH_DIR_NAME = 'AIMPSkipSilence';

const
  LOCALE_SYSTEM_DEFAULT = 2048;

const
  MAX_TRACK_LENGTH = 60 * 15;

implementation

{ TScanDatabase }

constructor TScanDatabase.Create(AFileName: String);
begin
  FFileName := AFileName;
  FItems := TObjectList<TAudioScanData>.Create;
end;

destructor TScanDatabase.Destroy;
begin
  FItems.Free;

  inherited Destroy;
end;

procedure TScanDatabase.Add(AudioScanData: TAudioScanData);
begin
  AudioScanData.DateTimeAdded := Now;
  FItems.Add(AudioScanData);
  CleanupDb;
end;

procedure TScanDatabase.Remove(AItem: TAudioScanData);
begin
  FItems.Remove(AItem);
end;

procedure TScanDatabase.CleanupDb;
var
  dtItem: TDateTime;
  itemRemove: TAudioScanData;
  i: Integer;
begin
  dtItem := Now;

  while FItems.Count > MAX_DB_ITEMS do
  begin
    itemRemove := nil;
    for i := 0 to FItems.Count-1 do
    begin
      if CompareDateTime(FItems[i].DateTimeAdded, dtItem) < 0 then
      begin
        dtItem := FItems[i].DateTimeAdded;
        itemRemove := FItems[i];
      end;
    end;
    if Assigned(itemRemove) then
      Remove(itemRemove)
    else
      Break;
  end;
end;

function TScanDatabase.Find(AudioFileName: String;
  var AItem: TAudioScanData): Boolean;
var
  item: TAudioScanData;
begin
  Result := False;

  for item in FItems do
  begin
    if (item.FileName = AudioFileName) then
    begin
      AItem := item;
      Result := True;
      Break;
    end;
  end;
end;

function TScanDatabase.FindIndex(AudioFileName: String;
  var AItem: TAudioScanData): Boolean;
var
  i: Integer;
begin
  Result := False;

  for i := 0 to FItems.Count-1 do
  begin
    if (FItems[i].FileName = AudioFileName) then
    begin
      AItem := FItems[i];
      Result := True;
      Break;
    end;
  end;
end;

procedure TScanDatabase.LoadFromFile;
var
  XmlDocument: IXMLDocument;
  Node: IXMLNode;
  ScanData: TAudioScanData;
  fs: TFormatSettings;
begin
  FItems.Clear;

  if FileExists(FFileName) then
  begin
    fs := TFormatSettings.Create(LOCALE_SYSTEM_DEFAULT);

    XmlDocument := TXMLDocument.Create(FFileName);
    Node := XmlDocument.DocumentElement.ChildNodes.First;
    while Assigned(Node) do
    begin
      if (Node.NodeName = 'item') then
      begin
        ScanData := TAudioScanData.Create;

        try
          ScanData.FileName := Node.ChildNodes['filename'].NodeValue;
          ScanData.Intro := StrToInt64(Node.ChildNodes['intro'].NodeValue);
          ScanData.Outro := StrToInt64(Node.ChildNodes['outro'].NodeValue);
          ScanData.IntroTime := StrToInt64(Node.ChildNodes['introtime'].NodeValue) / 1000;
          ScanData.OutroTime := StrToInt64(Node.ChildNodes['outrotime'].NodeValue) / 1000;
          ScanData.DateTimeAdded := StrToDateTime(Node.ChildNodes['added'].NodeValue, fs);
        except
          on E: Exception do
            OutputDebugString(PChar('TScanDatabase.LoadFromFile failed to read data. Error: ' + e.Message));
        end;

        FItems.Add(ScanData);
      end;
      Node := Node.NextSibling;
    end;
  end;
end;

procedure TScanDatabase.SaveToFile;
var
  XmlDocument: IXMLDocument;
  ItemNode, RootNode: IXMLNode;
  ScanData: TAudioScanData;
  i: Integer;
  fs: TFormatSettings;
begin
  CleanupDb;

  fs := TFormatSettings.Create(LOCALE_SYSTEM_DEFAULT);

  XmlDocument := NewXMLDocument;
  XmlDocument.Encoding := 'utf-8';
  XmlDocument.Options := [doNodeAutoIndent];

  RootNode := XmlDocument.AddChild('scandatabase');

  for i := 0 to FItems.Count-1 do
  begin
    ScanData := FItems[i];
    ItemNode := RootNode.AddChild('item');
    ItemNode.AddChild('filename').Text := ScanData.FileName;
    ItemNode.AddChild('intro').Text := IntToStr(ScanData.Intro);
    ItemNode.AddChild('outro').Text := IntToStr(ScanData.Outro);
    ItemNode.AddChild('introtime').Text := IntToStr(Trunc(ScanData.IntroTime * 1000));
    ItemNode.AddChild('outrotime').Text := IntToStr(Trunc(ScanData.OutroTime * 1000));
    ItemNode.AddChild('added').Text := DateTimeToStr(ScanData.DateTimeAdded, fs);
  end;

  try
    ForceDirectories(ExtractFileDir((FFileName)));
  except
    on E: Exception do
      OutputDebugString(PChar('TScanDatabase.SaveToFile|ForceDirectories|' + e.Message));
  end;

  try
    XmlDocument.SaveToFile(FFileName);
  except
    on E: Exception do
      OutputDebugString(PChar('TScanDatabase.SaveToFile|XmlDocument.SaveToFile|' + e.Message));
  end;
end;

end.
