unit ServiceWorker;

interface

uses
  Classes, SyncObjs;

type
  TProcessWorker = class(TThread)
  private
    FStopEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Stop;
  end;

implementation

uses
  SysUtils, ActiveX, ServiceCore;

constructor TProcessWorker.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FStopEvent := TEvent.Create(nil, True, False, '');
  // No Delphi XE6, a thread criada suspensa deve ser iniciada com Resume.
  Resume;
end;

destructor TProcessWorker.Destroy;
begin
  FStopEvent.Free;
  inherited Destroy;
end;

procedure TProcessWorker.Stop;
begin
  Terminate;
  FStopEvent.SetEvent;
end;

procedure TProcessWorker.Execute;
var
  Codigo: Integer;
  ResultadoCOM: HRESULT;
begin
  ResultadoCOM := CoInitialize(nil);
  try
    if Failed(ResultadoCOM) then
      raise Exception.CreateFmt('Falha ao inicializar COM: 0x%.8x', [ResultadoCOM]);
    while not Terminated do
    begin
      try
        Codigo := ServiceCore.ExecutarProcesso;
        ServiceCore.GravarLog('Execucao automatica finalizada. Codigo=' + IntToStr(Codigo));
      except
        on E: Exception do
          ServiceCore.GravarLog('ERRO NA THREAD DE SERVICO: ' + E.ClassName + ': ' + E.Message);
      end;
      if not Terminated then
        FStopEvent.WaitFor(ServiceCore.IntervaloProcessamento);
    end;
  finally
    CoUninitialize;
  end;
end;

end.
