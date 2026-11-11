unit ServiceHost;

interface

uses
  Windows, SysUtils, Classes, SvcMgr;

type
  TIniciarServico = function: Integer; stdcall;
  TPararServico = procedure; stdcall;

  TSiservWindowsService = class(TService)
  private
    FDllHandle: HMODULE;
    FIniciarServico: TIniciarServico;
    FPararServico: TPararServico;
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
    procedure ServiceExecute(Sender: TService);
    procedure CarregarDLL;
    procedure DescarregarDLL;
    procedure GravarLogHost(const Mensagem: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  SiservWindowsService: TSiservWindowsService;

implementation

{$R *.dfm}

constructor TSiservWindowsService.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DisplayName := 'Siserv Service';
  Name := 'SiservService';
  StartType := stAuto;
  AllowStop := True;
  AllowPause := False;
  Interactive := False;
  OnStart := ServiceStart;
  OnStop := ServiceStop;
  OnExecute := ServiceExecute;
end;

destructor TSiservWindowsService.Destroy;
begin
  DescarregarDLL;
  inherited Destroy;
end;

procedure TSiservWindowsService.CarregarDLL;
var
  NomeDLL: string;
begin
  NomeDLL := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'SiservService.dll';
  FDllHandle := LoadLibrary(PChar(NomeDLL));
  if FDllHandle = 0 then
    raise Exception.CreateFmt('Nao foi possivel carregar %s. Erro %d.',
      [NomeDLL, GetLastError]);
  @FIniciarServico := GetProcAddress(FDllHandle, 'IniciarServico');
  @FPararServico := GetProcAddress(FDllHandle, 'PararServico');
  if not Assigned(FIniciarServico) or not Assigned(FPararServico) then
    raise Exception.Create('As funcoes do SiservService.dll nao foram encontradas.');
end;

procedure TSiservWindowsService.GravarLogHost(const Mensagem: string);
var
  Arquivo: TextFile;
  Nome: string;
begin
  Nome := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'SiservServiceHost.log';
  try
    AssignFile(Arquivo, Nome);
    if FileExists(Nome) then
      Append(Arquivo)
    else
      Rewrite(Arquivo);
    try
      Writeln(Arquivo, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + Mensagem);
    finally
      CloseFile(Arquivo);
    end;
  except
    // O log nao pode impedir o servico de responder ao SCM.
  end;
end;

procedure TSiservWindowsService.DescarregarDLL;
begin
  if Assigned(FPararServico) then
    FPararServico();
  FPararServico := nil;
  FIniciarServico := nil;
  if FDllHandle <> 0 then
  begin
    FreeLibrary(FDllHandle);
    FDllHandle := 0;
  end;
end;

procedure TSiservWindowsService.ServiceStart(Sender: TService;
  var Started: Boolean);
begin
  Started := False;
  try
    CarregarDLL;
    GravarLogHost('DLL carregada; iniciando processamento.');
    if FIniciarServico() <> 0 then
      raise Exception.Create('A DLL nao conseguiu iniciar o processamento.');
    Started := True;
    GravarLogHost('Servico iniciado.');
  except
    on E: Exception do
    begin
      GravarLogHost('ERRO AO INICIAR: ' + E.ClassName + ': ' + E.Message);
      DescarregarDLL;
      raise;
    end;
  end;
end;

procedure TSiservWindowsService.ServiceStop(Sender: TService;
  var Stopped: Boolean);
begin
  DescarregarDLL;
  Stopped := True;
end;

procedure TSiservWindowsService.ServiceExecute(Sender: TService);
begin
  while not Terminated do
    ServiceThread.ProcessRequests(True);
end;

end.
