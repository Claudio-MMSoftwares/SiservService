program SiservServiceHost;

uses
  Windows, SysUtils;

const
  SERVICE_NAME = 'SiservService';

type
  TIniciarServico = function: Integer; stdcall;
  TPararServico = procedure; stdcall;
  TServiceStatusHandle = THandle;
  TServiceStatus = record
    dwServiceType: DWORD;
    dwCurrentState: DWORD;
    dwControlsAccepted: DWORD;
    dwWin32ExitCode: DWORD;
    dwServiceSpecificExitCode: DWORD;
    dwCheckPoint: DWORD;
    dwWaitHint: DWORD;
  end;
  TServiceCtrlHandler = procedure(Control: DWORD); stdcall;
  TServiceMain = procedure(Argc: DWORD; Argv: PPChar); stdcall;
  TServiceTableEntry = record
    lpServiceName: PChar;
    lpServiceProc: TServiceMain;
  end;

function RegisterServiceCtrlHandlerA(lpServiceName: PChar;
  lpHandlerProc: TServiceCtrlHandler): TServiceStatusHandle; stdcall;
  external 'advapi32.dll' name 'RegisterServiceCtrlHandlerA';
function SetServiceStatus(hServiceStatus: TServiceStatusHandle;
  var lpServiceStatus: TServiceStatus): BOOL; stdcall;
  external 'advapi32.dll' name 'SetServiceStatus';
function StartServiceCtrlDispatcherA(
  var lpServiceStartTable: TServiceTableEntry): BOOL; stdcall;
  external 'advapi32.dll' name 'StartServiceCtrlDispatcherA';

const
  SERVICE_WIN32_OWN_PROCESS = $00000010;
  SERVICE_ACCEPT_STOP = $00000001;
  SERVICE_ACCEPT_SHUTDOWN = $00000004;
  SERVICE_START_PENDING = $00000002;
  SERVICE_STOP_PENDING = $00000003;
  SERVICE_RUNNING = $00000004;
  SERVICE_STOPPED = $00000001;
  SERVICE_CONTROL_STOP = $00000001;
  SERVICE_CONTROL_SHUTDOWN = $00000005;
  ERROR_SERVICE_SPECIFIC_ERROR = 1066;

var
  ServiceStatusHandle: TServiceStatusHandle;
  ServiceStatus: TServiceStatus;
  StopEvent: THandle;
  StopCompleteEvent: THandle;
  DllHandle: HMODULE;
  IniciarServico: TIniciarServico;
  PararServico: TPararServico;

procedure GravarLog(const Mensagem: string);
var
  Arquivo: TextFile;
  Nome: string;
begin
  Nome := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'SiservServiceHost.log';
  try
    AssignFile(Arquivo, Nome);
    if FileExists(Nome) then Append(Arquivo) else Rewrite(Arquivo);
    try
      Writeln(Arquivo, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + Mensagem);
    finally
      CloseFile(Arquivo);
    end;
  except
  end;
end;

procedure InformarStatus(const Estado: DWORD; CodigoWin32: DWORD = NO_ERROR);
begin
  ServiceStatus.dwServiceType := SERVICE_WIN32_OWN_PROCESS;
  ServiceStatus.dwCurrentState := Estado;
  ServiceStatus.dwControlsAccepted := SERVICE_ACCEPT_STOP or SERVICE_ACCEPT_SHUTDOWN;
  ServiceStatus.dwWin32ExitCode := CodigoWin32;
  ServiceStatus.dwServiceSpecificExitCode := 0;
  ServiceStatus.dwCheckPoint := 0;
  ServiceStatus.dwWaitHint := 0;
  if (Estado = SERVICE_START_PENDING) or (Estado = SERVICE_STOP_PENDING) then
    ServiceStatus.dwWaitHint := 5000;
  SetServiceStatus(ServiceStatusHandle, ServiceStatus);
end;

procedure ServiceCtrlHandler(Control: DWORD); stdcall;
begin
  if (Control = SERVICE_CONTROL_STOP) or (Control = SERVICE_CONTROL_SHUTDOWN) then
  begin
    InformarStatus(SERVICE_STOP_PENDING);
    SetEvent(StopEvent);
  end;
end;

procedure FinalizarServicoThread(Parameter: Pointer); stdcall;
begin
  try
    if Assigned(PararServico) then
      PararServico();
    if DllHandle <> 0 then
    begin
      FreeLibrary(DllHandle);
      DllHandle := 0;
    end;
    GravarLog('Servico parado.');
  except
    on E: Exception do
      GravarLog('ERRO AO PARAR: ' + E.ClassName + ': ' + E.Message);
  end;
  InformarStatus(SERVICE_STOPPED);
  if StopCompleteEvent <> 0 then
    SetEvent(StopCompleteEvent);
end;

procedure ServiceMain(Argc: DWORD; Argv: PPChar); stdcall;
var
  NomeDLL: string;
  Codigo: Integer;
  ThreadId: DWORD;
begin
  ServiceStatusHandle := RegisterServiceCtrlHandlerA(PChar(SERVICE_NAME), @ServiceCtrlHandler);
  if ServiceStatusHandle = 0 then Exit;
  FillChar(ServiceStatus, SizeOf(ServiceStatus), 0);
  InformarStatus(SERVICE_START_PENDING);
  try
    StopEvent := CreateEvent(nil, True, False, nil);
    if StopEvent = 0 then
      RaiseLastOSError;
    StopCompleteEvent := CreateEvent(nil, True, False, nil);
    if StopCompleteEvent = 0 then
      RaiseLastOSError;
    NomeDLL := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'SiservService.dll';
    DllHandle := LoadLibrary(PChar(NomeDLL));
    if DllHandle = 0 then
      RaiseLastOSError;
    @IniciarServico := GetProcAddress(DllHandle, 'IniciarServico');
    @PararServico := GetProcAddress(DllHandle, 'PararServico');
    if not Assigned(IniciarServico) or not Assigned(PararServico) then
      raise Exception.Create('Funcoes do SiservService.dll nao encontradas.');
    Codigo := IniciarServico();
    if Codigo <> 0 then
      raise Exception.CreateFmt('IniciarServico retornou %d.', [Codigo]);
    GravarLog('Servico iniciado.');
    InformarStatus(SERVICE_RUNNING);
    WaitForSingleObject(StopEvent, INFINITE);
    InformarStatus(SERVICE_STOP_PENDING);
    if CreateThread(nil, 0, @FinalizarServicoThread, nil, 0, ThreadId) = 0 then
      raise Exception.Create('Nao foi possivel criar a thread de parada.');
    WaitForSingleObject(StopCompleteEvent, INFINITE);
    CloseHandle(StopEvent);
    CloseHandle(StopCompleteEvent);
  except
    on E: Exception do
    begin
      GravarLog('ERRO FATAL: ' + E.ClassName + ': ' + E.Message);
      if DllHandle <> 0 then FreeLibrary(DllHandle);
      if StopEvent <> 0 then CloseHandle(StopEvent);
      if StopCompleteEvent <> 0 then CloseHandle(StopCompleteEvent);
      InformarStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    end;
  end;
end;

var
  DispatchTable: array[0..1] of TServiceTableEntry;

begin
  DllHandle := 0;
  StopEvent := 0;
  StopCompleteEvent := 0;
  FillChar(DispatchTable, SizeOf(DispatchTable), 0);
  DispatchTable[0].lpServiceName := PChar(SERVICE_NAME);
  DispatchTable[0].lpServiceProc := @ServiceMain;
  if not StartServiceCtrlDispatcherA(DispatchTable[0]) then
    GravarLog('StartServiceCtrlDispatcher falhou: ' + IntToStr(GetLastError));
end.
