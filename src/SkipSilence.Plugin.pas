unit SkipSilence.Plugin;

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
  Winapi.Windows, System.SysUtils, System.Types, AIMPCustomPlugin,
  apiPlugin, apiMessages, apiCore, apiWrappers, SkipSilence.PlayerHook,
  bass;

type
  { TAIMPSkipSilencePlugin }

  TAIMPSkipSilencePlugin = class(TAIMPCustomPlugin)
  protected
    FServiceMessageDispatcher: IAIMPServiceMessageDispatcher;
    FMessageHook: IAIMPMessageHook;
    function InfoGet(Index: Integer): PWideChar; override;
    function InfoGetCategories: DWORD; override;
    function Initialize(Core: IAIMPCore): HRESULT; override; stdcall;
    procedure Finalize; override; stdcall;
    procedure SystemNotification(NotifyID: Integer; Data: IUnknown); override; stdcall;
  public
  end;

implementation

{ TAIMPSkipSilencePlugin }

function TAIMPSkipSilencePlugin.InfoGet(Index: Integer): PWideChar;
begin
  case Index of
    AIMP_PLUGIN_INFO_NAME:
      Result := 'Skip Silence';
    AIMP_PLUGIN_INFO_AUTHOR:
      Result := 'r1me';
    AIMP_PLUGIN_INFO_SHORT_DESCRIPTION:
      Result := 'Provides an ability to skip silence in begining and end of file.';
  else
    Result := nil;
  end;
end;

function TAIMPSkipSilencePlugin.InfoGetCategories: DWORD;
begin
  Result := AIMP_PLUGIN_CATEGORY_ADDONS;
end;

function TAIMPSkipSilencePlugin.Initialize(Core: IAIMPCore): HRESULT;
begin
  Result := inherited Initialize(Core);

  BASS_Init(-1, 44100, 0, 0, nil);

  if CoreGetService(IID_IAIMPServiceMessageDispatcher, FServiceMessageDispatcher) then
  begin
    FMessageHook := TPlaybackMessageHook.Create(Core) as IAIMPMessageHook;
    FServiceMessageDispatcher.Hook(FMessageHook);
  end;
end;

procedure TAIMPSkipSilencePlugin.Finalize;
begin
  if Assigned(FMessageHook) then
  begin
    FServiceMessageDispatcher.Unhook(FMessageHook);
    FMessageHook := nil;
  end;
  FServiceMessageDispatcher := nil;

  BASS_Stop;
  BASS_Free;
  
  inherited Finalize;
end;

procedure TAIMPSkipSilencePlugin.SystemNotification(NotifyID: Integer; Data: IUnknown); stdcall;
begin
  // do nothing
end;

end.
