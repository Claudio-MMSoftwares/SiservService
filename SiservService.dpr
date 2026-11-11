library SiservService;

uses
  IBC,
  Windows,
  System.SysUtils,
  Forms,
  System.Classes,
  ServiceDataModule in 'ServiceDataModule.pas' {ServiceDM: TServiceDataModule},
  PefService in 'C:\Siserv\CIOT\eFrete\PefService.pas',
  ServiceTAC in 'ServiceTAC.pas',
  ServiceCore in 'ServiceCore.pas',
  ServiceWorker in 'ServiceWorker.pas';

{$R *.res}

var
  ProcessWorker: TProcessWorker;

function ExecutarProcesso: Integer; stdcall;
begin
  try
    if not Assigned(Application) then
      Application.Initialize;
    if not Assigned(ServiceDM) then
      ServiceDM := TServiceDataModule.Create(nil);
    Result := ServiceCore.ExecutarProcesso;
  except
    on E: Exception do
    begin
      ServiceCore.GravarLog('ERRO FATAL: ' + E.ClassName + ': ' + E.Message);
      Result := 1;
    end;
  end;
end;

function IniciarServico: Integer; stdcall;
begin
  try
    if not Assigned(ServiceDM) then
      ServiceDM := TServiceDataModule.Create(nil);
    if not Assigned(ProcessWorker) then
      ProcessWorker := TProcessWorker.Create;
    Result := 0;
  except
    on E: Exception do
    begin
      ServiceCore.GravarLog('ERRO AO INICIAR SERVICO: ' + E.ClassName + ': ' + E.Message);
      Result := 1;
    end;
  end;
end;

procedure PararServico; stdcall;
begin
  if Assigned(ProcessWorker) then
  begin
    ProcessWorker.Stop;
    ProcessWorker.WaitFor;
    FreeAndNil(ProcessWorker);
  end;
  FreeAndNil(ServiceDM);
end;

procedure FinalizarProcesso; stdcall;
begin
  PararServico;
end;

exports
  ExecutarProcesso name 'ExecutarProcesso',
  IniciarServico name 'IniciarServico',
  PararServico name 'PararServico',
  FinalizarProcesso name 'FinalizarProcesso';

begin
end.
