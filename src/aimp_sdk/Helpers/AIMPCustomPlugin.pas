{************************************************}
{*                                              *}
{*          AIMP Programming Interface          *}
{*               v3.60 build 1400               *}
{*                                              *}
{*                Artem Izmaylov                *}
{*                (C) 2006-2014                 *}
{*                 www.aimp.ru                  *}
{*              ICQ: 345-908-513                *}
{*            Mail: support@aimp.ru             *}
{*                                              *}
{************************************************}

unit AIMPCustomPlugin;

{$I apiConfig.inc}

interface

uses
  Windows, apiCore, apiObjects, apiPlugin, apiWrappers;

type

  { TAIMPCustomPlugin }

  TAIMPCustomPlugin = class(TInterfacedObject, IAIMPPlugin)
  protected
    // IAIMPPlugin
    function InfoGet(Index: Integer): PWideChar; virtual; stdcall; abstract;
    function InfoGetCategories: DWORD; virtual; stdcall; abstract;
    function Initialize(Core: IAIMPCore): HRESULT; virtual; stdcall;
    procedure Finalize; virtual; stdcall;
    procedure SystemNotification(NotifyID: Integer; Data: IUnknown); virtual; stdcall; abstract;
  public
    // Services
    function ServiceGetConfig: TAIMPServiceConfig;
  end;

implementation

uses
  SysUtils, apiMUI;

{ TAIMPCustomPlugin }

function TAIMPCustomPlugin.ServiceGetConfig: TAIMPServiceConfig;
begin
  Result := TAIMPServiceConfig.Create;
end;

procedure TAIMPCustomPlugin.Finalize;
begin
  TAIMPAPIWrappers.Finalize;
end;

function TAIMPCustomPlugin.Initialize(Core: IAIMPCore): HRESULT;
begin
  TAIMPAPIWrappers.Initialize(Core);
  Result := S_OK;
end;

end.
