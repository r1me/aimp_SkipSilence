unit SkipSilence.ScanQueue;

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
  Winapi.Windows, System.Classes, System.SysUtils, System.Math, System.Generics.Collections,
  System.SyncObjs, SkipSilence.ScanDatabase, bass;

type
  TSafeQueue<T> = class
  strict private
    FQueue: TQueue<T>;
    FCriticalSection: TCriticalSection;
    FSemaphore: TSemaphore;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const Item: T);
    function Dequeue(var Item: T; Timeout: LongWord = INFINITE): TWaitResult;
  end;

type
  TScanWorker = class(TThread)
  protected
    FScanDatabase: TScanDatabase;
    FQueue: TSafeQueue<String>;
    procedure Execute; override;
  private
    function DetectSilence(ASilenceThreshold: Integer; AMaxLength: Single;
      var AudioScanData: TAudioScanData): Boolean;
  public
    procedure AddToQueue(AFileName: String);
    constructor Create(AScanDatabase: TScanDatabase);
    destructor Destroy; override;
  end;

implementation

{ TSafeQueue }

constructor TSafeQueue<T>.Create;
begin
  inherited Create;
  FCriticalSection := TCriticalSection.Create;
  FQueue := TQueue<T>.Create;
  FSemaphore := TSemaphore.Create(nil, 0, MaxInt, '');
end;

destructor TSafeQueue<T>.Destroy;
begin
  FreeAndNil(FQueue);
  FCriticalSection.Free;
  FSemaphore.Free;
  inherited Destroy;
end;

procedure TSafeQueue<T>.Enqueue(const Item: T);
begin
  FCriticalSection.Enter;
  try
    FQueue.Enqueue(Item);
  finally
    FCriticalSection.Leave;
  end;
  FSemaphore.Release;
end;

function TSafeQueue<T>.Dequeue(var Item: T; Timeout: LongWord): TWaitResult;
begin
  Result := FSemaphore.WaitFor(Timeout);
  if Result <> wrSignaled then Exit;
  FCriticalSection.Enter;
  try
    Item := FQueue.Dequeue;
  finally
    FCriticalSection.Leave;
  end;
end;

{ TScanWorker }

procedure TScanWorker.AddToQueue(AFileName: String);
begin
  if FileExists(AFileName) then
  begin
    FQueue.Enqueue(AFileName);
  end;
end;

constructor TScanWorker.Create(AScanDatabase: TScanDatabase);
begin
  inherited Create(True);

  FQueue := TSafeQueue<String>.Create;
  FScanDatabase := AScanDatabase;
end;

destructor TScanWorker.Destroy;
begin
  FQueue.Free;

  inherited;
end;

procedure TScanWorker.Execute;
var
  fileName: String;
  scanData: TAudioScanData;
begin
  while not Terminated do
  begin
    if FQueue.Dequeue(fileName, 500) = wrSignaled then
    begin
      scanData := TAudioScanData.Create;
      scanData.FileName := fileName;
      if DetectSilence(10000, MAX_TRACK_LENGTH, scanData) then
      begin
        FScanDatabase.Add(scanData);
        FScanDatabase.SaveToFile;
      end;
    end;
  end;
end;

function TScanWorker.DetectSilence(ASilenceThreshold: Integer; AMaxLength: Single;
  var AudioScanData: TAudioScanData): Boolean;
var
  buffer: array[0..50000] of Integer;
  count: LongInt;
  IntroSilence: Integer;
  OutroSilence: Integer;
  pos, len: QWORD;
  a, availData: Integer;
  decoderStream: DWORD;
  flags: DWORD;
  level: Single;
  silenceThreshold: Integer;
  normalizationGain: Single;
begin
  Result := False;

  OutroSilence := 0;

  flags := BASS_STREAM_PRESCAN or BASS_STREAM_DECODE;
  {$IFDEF UNICODE}
  flags := flags or BASS_UNICODE;
  {$ENDIF}

  decoderStream := BASS_StreamCreateFile(False, PChar(AudioScanData.FileName), 0, 0, flags);
  try
    len := BASS_ChannelGetLength(decoderStream, BASS_POS_BYTE);
    if len > 0 then
    begin
      OutroSilence := len;
      AudioScanData.Duration := BASS_ChannelBytes2Seconds(decoderStream, len);
      if CompareValue(AudioScanData.Duration, AMaxLength) > 0 then
        Exit;
    end;

    normalizationGain := 0.0;
    while (BASS_ChannelGetLevelEx(decoderStream, @level, 1, BASS_LEVEL_MONO)) do // get a mono level reading
      if CompareValue(normalizationGain, level) = -1 then normalizationGain := level; // found a higher peak

    if CompareValue(normalizationGain, 0.0) = 0 then
      normalizationGain := 1.0;

    BASS_ChannelSetPosition(decoderStream, 0, BASS_POS_BYTE);

    silenceThreshold := Round((1 / normalizationGain * ASilenceThreshold) * 1000);
    count := 0;
    // detect start silence
    repeat
      //decode some data
      availData := BASS_ChannelGetData(decoderStream, @buffer[0], Length(buffer));
      if (availData <= 0) then Break;
      //bytes -> samples
      availData := availData div 4;
      //count silent samples
      a := 0;
      while (a < availData) and (Abs(buffer[a]) <= silenceThreshold) do
        Inc(a);

      //add number of silent bytes
      count := count + (a * 4);
      //if sound has begun...
      if (a < availData) then
      begin
        //move back to a quieter sample (to avoid "click")
        while(a > (silenceThreshold / 4)) and (Abs(buffer[a]) > (silenceThreshold / 4)) do
        begin
          Dec(a);
          count := count - 16;
        end;
        Break;
      end;
    until (availData <= 0);
    if count < 0 then
      count := 0;
    IntroSilence := count;

    // detect end silence
    pos := len;
    while (pos > count) do
    begin
      //step back a bit
      if pos < 200000 then
        pos := 0
      else
        pos := pos - 200000;

      BASS_ChannelSetPosition(decoderStream, pos, BASS_POS_BYTE);

      availData := BASS_ChannelGetData(decoderStream, @buffer[0], 200000);
      if (availData <= 0) then Break;
      //bytes -> samples
      availData := availData div 4;
      //count silent samples
      a := availData;
      while (a > 0) and (Abs(buffer[a-1]) <= (silenceThreshold / 2)) do
        Dec(a);

      //if sound has begun...
      if (a>0) then
      begin
        //silence begins here
        count := pos + a*4;
        OutroSilence := count;
        Break;
      end;
    end;

    AudioScanData.Intro := IntroSilence;
    if count > 0 then
      AudioScanData.Outro := OutroSilence;

    AudioScanData.IntroTime := BASS_ChannelBytes2Seconds(decoderStream, AudioScanData.Intro);
    AudioScanData.OutroTime := BASS_ChannelBytes2Seconds(decoderStream, AudioScanData.Outro);
    AudioScanData.NormalizationGain := normalizationGain;

    Result := True;
  finally
    BASS_StreamFree(decoderStream);
  end;
end;

end.
