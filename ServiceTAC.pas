unit ServiceTAC;

interface

uses
  SysUtils, Classes, DB, DBAccess, IBC, Rio, SOAPHTTPClient, SOAPHTTPTrans,
  XSBuiltIns, JwaWinCrypt, WinINet,
  PefService, ServiceDataModule;

type
  TServicoTAC = class
  private
    FConexao: TIBCConnection;
    FUsuario: string;
    FNumeroSerieCertificado: string;
    FLogLinhas: TStringList;
    procedure AdicionarLog(const APrefixo, ATexto: string);
    procedure CarregaCertificado(const HTTPReqResp: THTTPReqResp; Data: Pointer);
    function ValorTextoParaFloat(const AValor: string): Double;
  public
    constructor Create(AConexao: TIBCConnection; const AUsuario: string);
    destructor Destroy; override;
    procedure Processar(const ANOTAC: Integer; out ATeveBaixa, ABaixaEncontrada: Boolean);
    property LogLinhas: TStringList read FLogLinhas;
  end;

implementation

const
  INTERNET_OPTION_CLIENT_CERT_CONTEXT = 84;
  CERT_STORE_PROV_SYSTEM_A_ID = 10;
  CERT_SYSTEM_STORE_LOCAL_MACHINE_FLAG = $00020000;
  CERT_STORE_OPEN_EXISTING_FLAG_VALUE = $00004000;
  X509_ASN_ENCODING_VALUE = $00000001;

function NormalizarSerial(const AValor: string): string;
begin
  Result := UpperCase(Trim(AValor));
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, ':', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

function SerialDoCertificado(const AContext: PCCERT_CONTEXT;
  AReverso: Boolean): string;
var
  I: Integer;
begin
  Result := '';
  if (AContext = nil) or (AContext^.pCertInfo = nil) then
    Exit;
  if AReverso then
    for I := AContext^.pCertInfo^.SerialNumber.cbData - 1 downto 0 do
      Result := Result + IntToHex(AContext^.pCertInfo^.SerialNumber.pbData[I], 2)
  else
    for I := 0 to AContext^.pCertInfo^.SerialNumber.cbData - 1 do
      Result := Result + IntToHex(AContext^.pCertInfo^.SerialNumber.pbData[I], 2);
end;

constructor TServicoTAC.Create(AConexao: TIBCConnection; const AUsuario: string);
begin
  FConexao := AConexao;
  FUsuario := AUsuario;
  FLogLinhas := TStringList.Create;
end;

destructor TServicoTAC.Destroy;
begin
  FLogLinhas.Free;
  inherited Destroy;
end;

procedure TServicoTAC.AdicionarLog(const APrefixo, ATexto: string);
begin
  FLogLinhas.Add(APrefixo + ' ' + ATexto);
end;

function TServicoTAC.ValorTextoParaFloat(const AValor: string): Double;
var
  Texto: string;
begin
  Texto := Trim(AValor);
  Texto := StringReplace(Texto, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Texto := StringReplace(Texto, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  Result := StrToFloatDef(Texto, 0);
end;

procedure TServicoTAC.CarregaCertificado(const HTTPReqResp: THTTPReqResp;
  Data: Pointer);
var
  Store: HCERTSTORE;
  CertContext: PCCERT_CONTEXT;
  NumeroSerial: string;
  Encontrado: Boolean;
begin
  NumeroSerial := NormalizarSerial(FNumeroSerieCertificado);
  if NumeroSerial = '' then
    raise Exception.Create('Número de série do certificado não informado.');

  // O serviço roda como LocalSystem; tente primeiro Local Computer/MY.
  Store := CertOpenStore(PAnsiChar(CERT_STORE_PROV_SYSTEM_A_ID), X509_ASN_ENCODING_VALUE, 0,
    CERT_SYSTEM_STORE_LOCAL_MACHINE_FLAG or CERT_STORE_OPEN_EXISTING_FLAG_VALUE,
    PWideChar('MY'));
  if Store = nil then
    Store := CertOpenStore(PAnsiChar(CERT_STORE_PROV_SYSTEM_A_ID), X509_ASN_ENCODING_VALUE, 0,
      CERT_SYSTEM_STORE_LOCAL_MACHINE_FLAG or CERT_STORE_OPEN_EXISTING_FLAG_VALUE,
      PAnsiChar('MY'));
  if Store = nil then
    Store := CertOpenSystemStore(0, 'MY');
  if Store = nil then
    raise Exception.Create('Não foi possível abrir Local Computer/MY ou Current User/MY.');
  Encontrado := False;
  CertContext := nil;
  try
    repeat
      CertContext := CertEnumCertificatesInStore(Store, CertContext);
      if CertContext = nil then
        Break;
      Encontrado :=
        (NormalizarSerial(SerialDoCertificado(CertContext, False)) = NumeroSerial) or
        (NormalizarSerial(SerialDoCertificado(CertContext, True)) = NumeroSerial);
    until Encontrado;

    if not Encontrado then
      raise Exception.Create(
        'Certificado EFrete não localizado em Local Computer/MY ou Current User/MY. ' +
        'Número de série: ' + FNumeroSerieCertificado);

    if not InternetSetOption(Data, INTERNET_OPTION_CLIENT_CERT_CONTEXT,
      CertContext, SizeOf(CERT_CONTEXT)) then
      raise Exception.Create('Não foi possível associar o certificado à conexão SOAP.');
  finally
    CertCloseStore(Store, 0);
  end;
end;

procedure TServicoTAC.Processar(const ANOTAC: Integer; out ATeveBaixa, ABaixaEncontrada: Boolean);
var
  TACQuery, IntegracaoQuery, AuxQuery: TIBCQuery;
  HTTPRIO: THTTPRIO;
  SOAP: PefServiceSoap;
  Req: ObterTransacoesRequest;
  Res: ObterTransacoesResult;
  DataInicial, DataFinal, DataPagamento: TDateTime;
  CNPJ, CIOT, ValorPago: string;
  CNPJMatriz: string;
  ValorPagoFloat: Double;
  I, NoTacPgto, ItemPgto, NoPg, NoParc, NoTipPag: Integer;
  Transacoes: ArrayOfTransacao;
  CNPJs: ArrayOfLong;
  CIOTs: ArrayOfString2;
  Dt: TXSDateTime;
  EncontrouParcela: Boolean;
begin
  ATeveBaixa := False;
  ABaixaEncontrada := False;
  TACQuery := TIBCQuery.Create(nil);
  IntegracaoQuery := TIBCQuery.Create(nil);
  AuxQuery := TIBCQuery.Create(nil);
  HTTPRIO := nil;
  try
    TACQuery.Connection := FConexao;
    TACQuery.SQL.Text :=
      'select tac.notac, tac.noemp, tac.nointegrador, tac.ciot, ' +
      '       coalesce(tac.ciot_gratuito, ''F'') ciot_gratuito, ' +
      '       integ.efrete, emp.cgcemp, emp.noemp_matriz, ' +
      '       empm.cgcemp as cgcemp_matriz, emp.ciot_efrete_hash, emp.ciot_cd ' +
      '  from tabcli_tac tac ' +
      ' inner join tabemp emp on emp.noemp = tac.noemp ' +
      ' left join tabemp empm on empm.noemp = emp.noemp_matriz ' +
      ' left join tabintegrador integ on integ.nointegrador = tac.nointegrador ' +
      ' where tac.notac = :notac';
    TACQuery.ParamByName('NOTAC').AsInteger := ANOTAC;
    TACQuery.Open;

    if TACQuery.IsEmpty then
      raise Exception.Create('TAC não localizado.');
    if not SameText(Trim(TACQuery.FieldByName('EFRETE').AsString), 'T') then
      raise Exception.Create('TAC localizado sem integrador EFrete.');
    if SameText(Trim(TACQuery.FieldByName('CIOT_GRATUITO').AsString), 'T') then
      Exit;

    CIOT := Trim(TACQuery.FieldByName('CIOT').AsString);
    if CIOT = '' then
      raise Exception.Create('CIOT não informado para consultar transações do EFrete.');

    IntegracaoQuery.Connection := FConexao;
    IntegracaoQuery.SQL.Text :=
      'select tabemp_integr.*, tabemp_integr.nobanco ' +
      '  from tabemp_integr ' +
      ' inner join tabintegrador on tabintegrador.nointegrador = tabemp_integr.nointegrador ' +
      ' where tabemp_integr.noemp = :noemp ' +
      '   and tabemp_integr.nointegrador = :nointegrador';
    IntegracaoQuery.ParamByName('NOEMP').AsInteger := TACQuery.FieldByName('NOEMP').AsInteger;
    IntegracaoQuery.ParamByName('NOINTEGRADOR').AsInteger := TACQuery.FieldByName('NOINTEGRADOR').AsInteger;
    IntegracaoQuery.Open;
    if IntegracaoQuery.IsEmpty then
      raise Exception.Create('Integração EFrete não localizada para a empresa.');
    if IntegracaoQuery.FieldByName('NOBANCO').AsInteger <= 0 then
      raise Exception.Create('Banco não informado no cadastro do integrador EFrete.');

    CNPJMatriz := TACQuery.FieldByName('CGCEMP_MATRIZ').AsString;
    if Trim(CNPJMatriz) = '' then
      CNPJMatriz := TACQuery.FieldByName('CGCEMP').AsString;
    CNPJ := StringReplace(StringReplace(StringReplace(CNPJMatriz, '.', '', [rfReplaceAll]), '/', '', [rfReplaceAll]), '-', '', [rfReplaceAll]);
    if CNPJ = '' then
      raise Exception.Create('CNPJ da empresa não localizado.');

    DataInicial := Date - 3;
    DataFinal := Date;
    Req := ObterTransacoesRequest.Create;
    Res := nil;
    try
      Req.Integrador := TACQuery.FieldByName('CIOT_EFRETE_HASH').AsString;
      Req.Versao := 1;
      Dt := TXSDateTime.Create;
      Dt.AsDateTime := DataInicial;
      Req.DataInicial := Dt;
      Dt := TXSDateTime.Create;
      Dt.AsDateTime := DataFinal;
      Req.DataFinal := Dt;
      SetLength(CIOTs, 1);
      CIOTs[0] := CIOT;
      Req.CIOTs := CIOTs;
      SetLength(CNPJs, 1);
      CNPJs[0] := StrToInt64(CNPJ);
      Req.MatrizCNPJ := CNPJs;

      HTTPRIO := THTTPRIO.Create(nil);
      FNumeroSerieCertificado :=
        Trim(TACQuery.FieldByName('CIOT_CD').AsString);
      if FNumeroSerieCertificado = '' then
        raise Exception.Create('Número de série do certificado não informado em TABEMP.CIOT_CD.');
      HTTPRIO.HTTPWebNode.OnBeforePost := CarregaCertificado;
      SOAP := GetPefServiceSoap(False, '', HTTPRIO);
      Res := SOAP.ObterTransacoes(Req);
      if not Assigned(Res) then
        raise Exception.Create('Resposta vazia ao consultar transações do EFrete.');
      if not Res.Sucesso then
        if Assigned(Res.Excecao) and (Trim(Res.Excecao.Mensagem) > '') then
          raise Exception.Create(Res.Excecao.Mensagem)
        else
          raise Exception.Create('Consulta de transações do EFrete retornou sem sucesso.');

      Transacoes := Res.Transacoes;
      AdicionarLog('[RESP]', 'Consulta Efrete - retorno por CIOT.');
      AdicionarLog('[RESP]', 'CIOT consultado: ' + CIOT);
      AdicionarLog('[RESP]', 'Quantidade de transações: ' + IntToStr(Length(Transacoes)));
      if Length(Transacoes) = 0 then
        AdicionarLog('[MSG]', 'Nenhuma transação retornada para o CIOT ' + CIOT + '.');
      AuxQuery.Connection := FConexao;
      for I := 0 to High(Transacoes) do
      begin
        AdicionarLog('[RESP]', 'ID: ' + Transacoes[I].Id);
        AdicionarLog('[RESP]', 'CIOT: ' + Transacoes[I].CIOT);
        AdicionarLog('[RESP]', 'DocumentoViagem: ' + Transacoes[I].DocumentoViagem);
        AdicionarLog('[RESP]', 'TransacaoDoCIOT: ' + IntToStr(Transacoes[I].TransacaoDoCIOT));
        if Ord(Transacoes[I].Status) <> 0 then
        begin
          AdicionarLog('[MSG]', 'Transação ignorada por status não ativo.');
          Continue;
        end;
        // Apenas adiantamentos são baixados automaticamente. Os demais tipos
        // de cobrança continuam disponíveis no retorno da EFrete, mas não
        // devem gerar baixa neste serviço.
        if Ord(Transacoes[I].TipoDeCobranca) <> 1 then
        begin
          AdicionarLog('[MSG]', 'Transação ignorada: não é adiantamento.');
          Continue;
        end;
        if Assigned(Transacoes[I].ValorPago) then
          ValorPago := Transacoes[I].ValorPago.DecimalString
        else
          ValorPago := '0';
        ValorPagoFloat := ValorTextoParaFloat(ValorPago);
        if Assigned(Transacoes[I].DataDeOperacao) then
          DataPagamento := Transacoes[I].DataDeOperacao.AsDateTime
        else
          DataPagamento := Date;

        AuxQuery.Close;
        AuxQuery.SQL.Text :=
          'select first 1 pgto.notac, pgto.item, pgto.nopg, pgto.noparc, pgto.notippag ' +
          '  from tabcli_tac tac ' +
          ' inner join tabcli_tac_pgto pgto on pgto.notac = tac.notac ' +
          ' left join tabtippgtomot tipo on tipo.notippgtomot = pgto.notippgtomot ' +
          ' where tac.ciot = :ciot and pgto.noparc = :noparc ' +
          '   and tipo.adiant = ''T'' ' +
          ' order by pgto.item';
        AuxQuery.ParamByName('CIOT').AsString := Transacoes[I].CIOT;
        AuxQuery.ParamByName('NOPARC').AsInteger := Transacoes[I].TransacaoDoCIOT;
        AuxQuery.Open;
        EncontrouParcela := not AuxQuery.IsEmpty;
        if not EncontrouParcela then
        begin
          AdicionarLog('[MSG]', 'Nenhuma parcela localizada para baixa EFrete. CIOT ' +
            Transacoes[I].CIOT + ', TransacaoDoCIOT ' +
            IntToStr(Transacoes[I].TransacaoDoCIOT));
          Continue;
        end;

        NoTacPgto := AuxQuery.FieldByName('NOTAC').AsInteger;
        ItemPgto := AuxQuery.FieldByName('ITEM').AsInteger;
        NoPg := AuxQuery.FieldByName('NOPG').AsInteger;
        NoParc := AuxQuery.FieldByName('NOPARC').AsInteger;
        NoTipPag := AuxQuery.FieldByName('NOTIPPAG').AsInteger;

        AuxQuery.Close;
        AuxQuery.SQL.Text := 'select first 1 item from tabpg_pgto where nopg = :nopg and noparc = :noparc';
        AuxQuery.ParamByName('NOPG').AsInteger := NoPg;
        AuxQuery.ParamByName('NOPARC').AsInteger := NoParc;
        AuxQuery.Open;
        if not AuxQuery.IsEmpty then
        begin
          ABaixaEncontrada := True;
          AdicionarLog('[MSG]', 'Baixa já existente para Título ' + IntToStr(NoPg) + '/' +
            IntToStr(NoParc) + ', CIOT ' + Transacoes[I].CIOT);
          Continue;
        end;

        AuxQuery.Close;
        AuxQuery.SQL.Text :=
          'select nobanconc from tabban_conc where nobanco = :nobanco ' +
          'and dataconc = :dataconc and travado = ''T''';
        AuxQuery.ParamByName('NOBANCO').AsInteger := IntegracaoQuery.FieldByName('NOBANCO').AsInteger;
        AuxQuery.ParamByName('DATACONC').AsDate := Trunc(DataPagamento);
        AuxQuery.Open;
        if not AuxQuery.IsEmpty then
          raise Exception.Create('A conciliação bancária está travada.');

        if not FConexao.InTransaction then
          FConexao.StartTransaction;
        try
          AuxQuery.Close;
          AuxQuery.SQL.Text :=
            'insert into tabpg_pgto(nopg, noparc, item, datapgto, usuario, notippag, ' +
            'vlrjuros, vlrdesconto, vlrpgtototal, nobanco_pg, vlrpgto, conc, dataconc) ' +
            'values(:nopg, :noparc, 1, :datapgto, :usuario, :notippag, 0, 0, ' +
            ':vlrtotal, :nobanco, :vlr, ''T'', :dataconc)';
          AuxQuery.ParamByName('NOPG').AsInteger := NoPg;
          AuxQuery.ParamByName('NOPARC').AsInteger := NoParc;
          AuxQuery.ParamByName('DATAPGTO').AsDateTime := DataPagamento;
          AuxQuery.ParamByName('USUARIO').AsString := FUsuario;
          AuxQuery.ParamByName('NOTIPPAG').AsInteger := NoTipPag;
          AuxQuery.ParamByName('VLRTOTAL').AsFloat := ValorPagoFloat;
          AuxQuery.ParamByName('NOBANCO').AsInteger := IntegracaoQuery.FieldByName('NOBANCO').AsInteger;
          AuxQuery.ParamByName('VLR').AsFloat := ValorPagoFloat;
          AuxQuery.ParamByName('DATACONC').AsDate := Trunc(DataPagamento);
          AuxQuery.ExecSQL;

          AuxQuery.Close;
          AuxQuery.SQL.Text := 'update tabpg set totalpago = :totalpago where nopg = :nopg and noparc = :noparc';
          AuxQuery.ParamByName('TOTALPAGO').AsFloat := ValorPagoFloat;
          AuxQuery.ParamByName('NOPG').AsInteger := NoPg;
          AuxQuery.ParamByName('NOPARC').AsInteger := NoParc;
          AuxQuery.ExecSQL;

          AuxQuery.Close;
          AuxQuery.SQL.Text :=
            'update tabcli_tac_pgto set liberarpgto = ''T'', protocolo = :protocolo, ' +
            'statusintegr = ''BAIXADO AUTOMATICO EFRETE'' where notac = :notac and item = :item';
          AuxQuery.ParamByName('PROTOCOLO').AsString := Transacoes[I].Id;
          AuxQuery.ParamByName('NOTAC').AsInteger := NoTacPgto;
          AuxQuery.ParamByName('ITEM').AsInteger := ItemPgto;
          AuxQuery.ExecSQL;
          FConexao.CommitRetaining;
          ATeveBaixa := True;
          AdicionarLog('[MSG]', 'Baixa EFrete realizada -> Contrato ' + IntToStr(NoTacPgto) +
            ', Item ' + IntToStr(ItemPgto) + ', Título ' + IntToStr(NoPg) + '/' +
            IntToStr(NoParc) + ', CIOT ' + Transacoes[I].CIOT +
            ', ValorPago ' + ValorPago);
        except
          FConexao.RollbackRetaining;
          raise;
        end;
      end;
      AdicionarLog('[MSG]', 'Transações do Efrete consultadas com sucesso.');
    finally
      Res.Free;
      Req.Free;
      // SOAP e HTTPRIO não devem ser liberados manualmente neste ponto.
      // A interface SOAP será finalizada automaticamente pelo Delphi.
    end;
  finally
    AuxQuery.Free;
    IntegracaoQuery.Free;
    TACQuery.Free;
  end;
end;

end.
