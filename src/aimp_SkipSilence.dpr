library aimp_SkipSilence;



uses
  apiPlugin,
  bass in 'bass.pas',
  SkipSilence.Plugin in 'SkipSilence.Plugin.pas',
  SkipSilence.PlayerHook in 'SkipSilence.PlayerHook.pas',
  SkipSilence.ScanDatabase in 'SkipSilence.ScanDatabase.pas',
  SkipSilence.ScanQueue in 'SkipSilence.ScanQueue.pas';

{$R *.res}

function AIMPPluginGetHeader(out Header: IAIMPPlugin): HRESULT; stdcall;
begin
  try
    Header := TAIMPSkipSilencePlugin.Create;
    Result := S_OK;
  except
    Result := E_UNEXPECTED;
  end;
end;

exports
  AIMPPluginGetHeader;

begin
end.
