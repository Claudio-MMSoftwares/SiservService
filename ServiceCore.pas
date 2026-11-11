unit ServiceCore;

interface

uses
  SysUtils, Classes, IniFiles, DBAccess, IBC, Forms, ServiceDataModule, ServiceTAC;

function ExecutarProcesso: Integer;
procedure GravarLog(const AMensagem: string);
function IntervaloProcessamento: Cardinal;

implementation

function NomeArquivoIni: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
  if SameText(ExtractFileName(Result), 'SiservService.ini') = False then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) +
      'SiservService.ini';
end;

procedure GravarLinhasLog(const ALinhas: TStrings);
var
  I: Integer;
begin
  if not Assigned(ALinhas) then
    Exit;
  for I := 0 to ALinhas.Count - 1 do
    GravarLog(ALinhas[I]);
end;

function NomeArquivoLog: string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(NomeArquivoIni);
  try
    Result := Ini.ReadString('Log', 'Arquivo',
      IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) +
      'SiservService.log');
  finally
    Ini.Free;
  end;
  if ExtractFilePath(Result) = '' then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) + Result;
end;

procedure GravarLog(const AMensagem: string);
var
  F: TextFile;
  Arquivo, Pasta: string;
begin
  Arquivo := NomeArquivoLog;
  Pasta := ExtractFilePath(Arquivo);
  if Pasta <> '' then
    ForceDirectories(Pasta);
  AssignFile(F, Arquivo);
  try
    if FileExists(Arquivo) then
      Append(F)
    else
      Rewrite(F);
    Writeln(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + AMensagem);
  finally
    CloseFile(F);
  end;
end;

function DataConfigurada(Ini: TIniFile; const AChave: string; ADefault: TDateTime): TDateTime;
var
  S: string;
begin
  S := Trim(Ini.ReadString('Processamento', AChave, ''));
  if S = '' then
    Exit(ADefault);
  try
    Result := StrToDate(S);
  except
    GravarLog('Data invalida no INI (' + AChave + '): ' + S);
    Result := ADefault;
  end;
end;

function IntervaloProcessamento: Cardinal;
var
  Ini: TIniFile;
  Minutos: Integer;
begin
  Ini := TIniFile.Create(NomeArquivoIni);
  try
    Minutos := Ini.ReadInteger('Processamento', 'IntervaloMinutos', 15);
  finally
    Ini.Free;
  end;
  if Minutos < 1 then
    Minutos := 1;
  Result := Cardinal(Minutos) * 60000;
end;

function ExecutarTAC: Integer;
var
  Ini: TIniFile;
  Q: TIBCQuery;
  ServicoTAC: TServicoTAC;
  DataIni, DataFim: TDateTime;
  Notac: Integer;
  TeveBaixa, BaixaEncontrada: Boolean;
  Total, Sucesso, Encontrada, SemPagamento, Erros: Integer;
begin
  Result := 1;
  Ini := TIniFile.Create(NomeArquivoIni);
  Q := TIBCQuery.Create(nil);
  ServicoTAC := nil;
  try
    Q.Connection := ServiceDM.DBConnec;
    Q.SQL.Text :=
      'select tabpg.notac ' +
      '  from tabpg ' +
      ' inner join tabintegrador on tabintegrador.nointegrador = tabpg.nointegrador ' +
      ' where tabpg.notac > 0 ' +
      '   and coalesce(tabintegrador.efrete, ''F'') = ''T'' ' +
      '   and (tabpg.cancelado = ''F'' or tabpg.cancelado is null) ' +
      '   and (tabpg.arquivar = ''F'' or tabpg.arquivar is null) ' +
      '   and (((select ciot_gratuito from tabcli_tac where tabcli_tac.notac = tabpg.notac) = ''F'') ' +
      '     or ((select ciot_gratuito from tabcli_tac where tabcli_tac.notac = tabpg.notac) is null)) ' +
      ' group by tabpg.notac ' +
      'having sum(coalesce(tabpg.totpg, 0) - coalesce(tabpg.totalpago, 0) - coalesce(tabpg.despg, 0)) > 0.01 ' +
      ' order by tabpg.notac';
    Q.Open;

    Total := 0;
    Sucesso := 0;
    Encontrada := 0;
    SemPagamento := 0;
    Erros := 0;
    while not Q.Eof do
    begin
      Inc(Total);
      Notac := Q.FieldByName('NOTAC').AsInteger;
      try
        ServicoTAC := TServicoTAC.Create(ServiceDM.DBConnec, ServiceDM.Usuario);
        try
          ServicoTAC.Processar(Notac, TeveBaixa, BaixaEncontrada);
          GravarLinhasLog(ServicoTAC.LogLinhas);
          if TeveBaixa then
          begin
            Inc(Sucesso);
            GravarLog(Format('TAC %d processado com baixa.', [Notac]));
          end
          else if BaixaEncontrada then
          begin
            Inc(Encontrada);
            GravarLog(Format('TAC %d ja possuia baixa.', [Notac]));
          end
          else
          begin
            Inc(SemPagamento);
            GravarLog(Format('TAC %d consultado sem pagamento localizado.', [Notac]));
          end;
        finally
          ServicoTAC.Free;
        end;
      except
        on E: Exception do
        begin
          if Assigned(ServicoTAC) then
            GravarLinhasLog(ServicoTAC.LogLinhas);
          Inc(Erros);
          GravarLog(Format('ERRO TAC %d: %s: %s', [Notac, E.ClassName, E.Message]));
        end;
      end;
      Q.Next;
    end;
    GravarLog(Format('FINALIZADO. Analisados=%d; Baixas=%d; Já baixados=%d; Sem pagamento=%d; Erros=%d',
      [Total, Sucesso, Encontrada, SemPagamento, Erros]));
    Result := Ord(Erros > 0);
  finally
    Q.Free;
    Ini.Free;
  end;
end;

function ExecutarProcesso: Integer;
begin
  Result := 1;
  Result := ExecutarTAC;
end;


end.
