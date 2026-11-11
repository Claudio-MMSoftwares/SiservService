unit MainForm;

interface

uses
  Windows, SysUtils, Classes, Forms, Controls, StdCtrls, ExtCtrls, IniFiles;

type
  TExecutarProcesso = function: Integer; stdcall;
  TIniciarServico = function: Integer; stdcall;
  TFinalizarProcesso = procedure; stdcall;
  TPararServico = procedure; stdcall;
  TFrmSiservService = class(TForm)
    TimerProcessamento: TTimer;
    ExecutarButton: TButton;
    StatusLabel: TLabel;
    LogMemo: TMemo;
    Panel1: TPanel;
    procedure ExecutarClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
  private
    FExecutando: Boolean;
    FHandle: HMODULE;
    FIniciarServico: TIniciarServico;
    FPararServico: TPararServico;
    procedure Executar;
    procedure IniciarServicoDLL;
    procedure CarregarLog;
    function IntervaloMs: Cardinal;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  FrmSiservService: TFrmSiservService;

implementation

{$R *.dfm}

function ArquivoIni: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) +
    'SiservService.ini';
end;

function ArquivoLog: string;
var
  Ini: TIniFile;
  Nome: string;
begin
  Ini := TIniFile.Create(ArquivoIni);
  try
    Nome := Ini.ReadString('Log', 'Arquivo', 'SiservService.log');
  finally
    Ini.Free;
  end;
  if ExtractFilePath(Nome) = '' then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) + Nome
  else
    Result := Nome;
end;

constructor TFrmSiservService.Create(AOwner: TComponent);
var
  Ini: TIniFile;
begin
  inherited Create(AOwner);
  // Criado em runtime para evitar falha do designer antigo ao desserializar
  // o TTimer no DFM (xmlrtl200.bpl).
  TimerProcessamento := TTimer.Create(Self);
  TimerProcessamento.Name := 'TimerProcessamento';
  TimerProcessamento.Enabled := False;
  TimerProcessamento.Interval := 1000;
  ExecutarButton.OnClick := ExecutarClick;
  TimerProcessamento.OnTimer := TimerTick;
  Ini := TIniFile.Create(ArquivoIni);
  try
    // Este timer apenas atualiza a tela; o processamento fica na thread da DLL.
    TimerProcessamento.Interval := 1000;
    TimerProcessamento.Enabled := True;
    StatusLabel.Caption := Format('Ativo. Intervalo: %d minuto(s).',
      [TimerProcessamento.Interval div 60000]);
    CarregarLog;
    IniciarServicoDLL;
  finally
    Ini.Free;
  end;
end;

destructor TFrmSiservService.Destroy;
begin
  if Assigned(FPararServico) then
    FPararServico();
  if FHandle <> 0 then
    FreeLibrary(FHandle);
  inherited Destroy;
end;

procedure TFrmSiservService.IniciarServicoDLL;
var
  DLL: string;
begin
  DLL := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) +
    'SiservService.dll';
  FHandle := LoadLibrary(PChar(DLL));
  if FHandle = 0 then
    raise Exception.CreateFmt('Nao foi possivel carregar %s. Erro %d.', [DLL, GetLastError]);
  @FIniciarServico := GetProcAddress(FHandle, 'IniciarServico');
  @FPararServico := GetProcAddress(FHandle, 'PararServico');
  if not Assigned(FIniciarServico) or not Assigned(FPararServico) then
    raise Exception.Create('As funcoes IniciarServico/PararServico nao foram encontradas no DLL.');
  if FIniciarServico() <> 0 then
    raise Exception.Create('A DLL nao conseguiu iniciar o servico.');
  StatusLabel.Caption := 'Servico ativo. Intervalo controlado pela DLL/INI.';
end;

procedure TFrmSiservService.CarregarLog;
var
  Linhas: TStringList;
begin
  if not FileExists(ArquivoLog) then
    Exit;
  Linhas := TStringList.Create;
  try
    Linhas.LoadFromFile(ArquivoLog);
    LogMemo.Lines.BeginUpdate;
    try
      LogMemo.Lines.Assign(Linhas);
      if LogMemo.Lines.Count > 0 then
        LogMemo.SelStart := Length(LogMemo.Text);
    finally
      LogMemo.Lines.EndUpdate;
    end;
  finally
    Linhas.Free;
  end;
end;

function TFrmSiservService.IntervaloMs: Cardinal;
var
  Minutos: Integer;
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ArquivoIni);
  try
    Minutos := Ini.ReadInteger('Processamento', 'IntervaloMinutos', 15);
  finally
    Ini.Free;
  end;
  if Minutos < 1 then Minutos := 1;
  Result := Cardinal(Minutos) * 60000;
end;

procedure TFrmSiservService.ExecutarClick(Sender: TObject);
begin
  CarregarLog;
end;

procedure TFrmSiservService.TimerTick(Sender: TObject);
begin
  CarregarLog;
end;

procedure TFrmSiservService.Executar;
var
  Handle: HMODULE;
  Funcao: TExecutarProcesso;
  Finalizar: TFinalizarProcesso;
  Codigo: Integer;
  DLL: string;
begin
  if FExecutando then Exit;
  FExecutando := True;
  TimerProcessamento.Enabled := False;
  try
    DLL := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) + 'SiservService.dll';
    Handle := LoadLibrary(PChar(DLL));
    if Handle = 0 then
      raise Exception.CreateFmt('Nao foi possivel carregar %s. Erro %d.', [DLL, GetLastError]);
    try
      @Funcao := GetProcAddress(Handle, 'ExecutarProcesso');
      if not Assigned(Funcao) then
        raise Exception.Create('A funcao ExecutarProcesso nao foi encontrada no DLL.');
      StatusLabel.Caption := 'Executando...';
      LogMemo.Lines.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' Inicio.');
      Codigo := Funcao();
      CarregarLog;
      LogMemo.Lines.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + Format(' Fim. Codigo=%d.', [Codigo]));
      StatusLabel.Caption := 'Aguardando proxima execucao.';
    finally
      @Finalizar := GetProcAddress(Handle, 'FinalizarProcesso');
      if Assigned(Finalizar) then
        Finalizar();
      FreeLibrary(Handle);
    end;
  except
    on E: Exception do
    begin
      StatusLabel.Caption := 'Erro.';
      CarregarLog;
      LogMemo.Lines.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + E.Message);
    end;
  end;
  TimerProcessamento.Interval := IntervaloMs;
  TimerProcessamento.Enabled := True;
  FExecutando := False;
end;

end.

