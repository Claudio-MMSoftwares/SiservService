unit ServiceDataModule;

interface

uses
  SysUtils, Classes, Forms, IniFiles, DBAccess, IBC, Data.DB;

type
  TServiceDataModule = class(TDataModule)
    Transaction: TIBCTransaction;
    DBConnec: TIBCConnection;
    procedure DataModuleCreate(Sender: TObject);
  private
    FUsuario: string;
    function ArquivoIni: string;
    function Descriptografar(const AValor: string): string;
  public
    property Usuario: string read FUsuario;
  end;

var
  ServiceDM: TServiceDataModule;

implementation

{$R *.dfm}

function TServiceDataModule.ArquivoIni: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) +
    'SiservService.ini';
end;

function TServiceDataModule.Descriptografar(const AValor: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AValor) do
    Result := Result + Chr(Ord(AValor[I]) + 20);
end;

procedure TServiceDataModule.DataModuleCreate(Sender: TObject);
var
  Ini: TIniFile;
  Senha: string;
begin
  Ini := TIniFile.Create(ArquivoIni);
  try
    DBConnec.Server := Ini.ReadString('Banco', 'Servidor', '127.0.0.1');
    DBConnec.Database := Ini.ReadString('Banco', 'Database', '');
    DBConnec.Port := Ini.ReadString('Banco', 'Porta', '3050');
    DBConnec.Username := Ini.ReadString('Banco', 'Usuario', 'sysdba');
    Senha := Ini.ReadString('Banco', 'Senha', '');
    if Ini.ReadBool('Banco', 'SenhaCriptografada', False) then
      Senha := Descriptografar(Senha);
    DBConnec.Password := Senha;
    DBConnec.SQLDialect := Ini.ReadInteger('Banco', 'SQLDialect', 1);
    DBConnec.Options.Charset := Ini.ReadString('Banco', 'Charset', 'WIN1252');
    DBConnec.Options.Role := Ini.ReadString('Banco', 'Role', '');
    DBConnec.ClientLibrary := Ini.ReadString('Banco', 'ClientLibrary', '');
    FUsuario := Ini.ReadString('Banco', 'UsuarioSistema', 'SiservService');
    if Trim(DBConnec.Database) = '' then
      raise Exception.Create('Banco.Database nao foi informado no SiservService.ini.');
    DBConnec.Connected := True;
  finally
    Ini.Free;
  end;
end;

end.
