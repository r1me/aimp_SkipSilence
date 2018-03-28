unit SkipSilence.PlayerHook;

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
  Winapi.Windows, System.Classes, System.SysUtils, System.Math,
  apiMessages, apiFileManager, apiObjects, apiPlayer, apiPlaylists, apiCore, apiWrappers,
  SkipSilence.ScanDatabase, SkipSilence.ScanQueue;

type
  TPlaybackMessageHook = class(TInterfacedObject, IAIMPMessageHook)
  private
    FServicePlayer: IAIMPServicePlayer;
    FServicePlaybackQueue: IAIMPServicePlaybackQueue;
    FScanDatabase: TScanDatabase;
    FFileName: String;
    FFoundDbTrack: Boolean;
    FCurrentTrackOutro: Double;
    FScanWorker: TScanWorker;
    procedure ScanSurroundingFiles;
  protected
    procedure CoreMessage(Message: DWORD; Param1: Integer; Param2: Pointer; var Result: HRESULT); stdcall;
  public
    constructor Create(Core: IAIMPCore); virtual;
    destructor Destroy; override;
  end;

implementation

{ TPlaybackMessageHook }

procedure TPlaybackMessageHook.CoreMessage(Message: DWORD; Param1: Integer;
  Param2: Pointer; var Result: HRESULT);
var
  currPos, trackDur: Double;
  fileInfo: IAIMPFileInfo;
  fileName: IAIMPString;
  scanData: TAudioScanData;
begin
  case Message of
    AIMP_MSG_EVENT_STREAM_START:
      begin
        FFoundDbTrack := False;
        FCurrentTrackOutro := -1;

        FServicePlayer.GetPosition(currPos);
        // Check db for existing data
        FServicePlayer.GetInfo(fileInfo);
        if Assigned(fileInfo) then
        begin
          ScanSurroundingFiles;

          fileInfo.GetValueAsObject(AIMP_FILEINFO_PROPID_FILENAME, IID_IAIMPString, fileName);
          if fileName.GetLength > 0 then
          begin
            FFileName := String(fileName.GetData);
            if FileExists(FFileName) then
            begin
              if FScanDatabase.Find(FFileName, scanData) then
              begin
                FServicePlayer.GetDuration(trackDur);
                if (CompareValue(trackDur, MAX_TRACK_LENGTH) > 0) or
                   (CompareValue(currPos, 0.5) > 0) then
                  Exit;

                FServicePlayer.SetPosition(scanData.IntroTime);
                FFoundDbTrack := True;
                FCurrentTrackOutro := scanData.OutroTime;
              end;
            end;
          end;
        end;
      end;
    AIMP_MSG_EVENT_PLAYER_UPDATE_POSITION:
      begin
        if not FFoundDbTrack then
        begin
          FFoundDbTrack := FScanDatabase.Find(FFileName, scanData);
          if FFoundDbTrack then
            FCurrentTrackOutro := scanData.OutroTime;
        end;

        if FFoundDbTrack then
        begin
          FServicePlayer.GetPosition(currPos);
          if currPos >= FCurrentTrackOutro then
            FServicePlayer.GoToNext;
        end;
      end;
  end;

  Result := E_NOTIMPL;
end;

constructor TPlaybackMessageHook.Create(Core: IAIMPCore);
var
  profilePath: IAIMPString;
  sDbPath: String;
begin
  CoreGetService(IID_IAIMPServicePlayer, FServicePlayer);
  CoreGetService(IID_IAIMPServicePlaybackQueue, FServicePlaybackQueue);

  Core.GetPath(AIMP_CORE_PATH_PROFILE, profilePath);
  sDbPath := IncludeTrailingPathDelimiter(String(profilePath.GetData)) + DB_PATH_DIR_NAME + '\' + DB_FILE_NAME;

  FScanDatabase := TScanDatabase.Create(sDbPath);
  FScanDatabase.LoadFromFile;
  FScanWorker := TScanWorker.Create(FScanDatabase);
  FScanWorker.Priority := tpLower;
  FScanWorker.Start;
end;

destructor TPlaybackMessageHook.Destroy;
begin
  FScanWorker.Free;

  FScanDatabase.SaveToFile;
  FScanDatabase.Free;

  FServicePlayer := nil;
  FServicePlaybackQueue := nil;

  inherited;
end;

procedure TPlaybackMessageHook.ScanSurroundingFiles;

  function GetQueueItemFileName(AQueueItem: IAIMPPlaybackQueueItem): String;
  var
    playlistItem: IAIMPPlaylistItem;
    fileName: IAIMPString;
  begin
    Result := '';

    AQueueItem.GetValueAsObject(AIMP_PLAYBACKQUEUEITEM_PROPID_PLAYLISTITEM,
      IID_IAIMPPlaylistItem, playlistItem);
    if Assigned(playlistItem) then
    begin
      playlistItem.GetValueAsObject(AIMP_PLAYLISTITEM_PROPID_FILENAME,
        IID_IAIMPString, fileName);
      if fileName.GetLength > 0 then
        Result := String(fileName.GetData);
    end;
  end;

var
  queueItem: IAIMPPlaybackQueueItem;
  playlistItem: IAIMPPlaylistItem;
  fileName: IAIMPString;
  scanList: array[0..2] of String;
  scanData: TAudioScanData;
  i: Integer;
begin
  // Current track
  if FServicePlayer.GetPlaylistItem(playlistItem) = S_OK then
  begin
    playlistItem.GetValueAsObject(AIMP_PLAYLISTITEM_PROPID_FILENAME,
      IID_IAIMPString, fileName);
    if fileName.GetLength > 0 then
      scanList[0] := String(fileName.GetData);
  end;
  // Next track
  if FServicePlaybackQueue.GetNextTrack(queueItem) = S_OK then
    scanList[1] := GetQueueItemFileName(queueItem);
  // Previous track
  if FServicePlaybackQueue.GetPrevTrack(queueItem) = S_OK then
    scanList[2] := GetQueueItemFileName(queueItem);

  for i := Low(scanList) to High(scanList) do
  begin
    if not FScanDatabase.Find(scanList[i], scanData) then
      FScanWorker.AddToQueue(scanList[i]);
  end;
end;

end.
