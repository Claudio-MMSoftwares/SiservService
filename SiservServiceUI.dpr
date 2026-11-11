program SiservServiceUI;

uses
  Forms,
  MainForm in 'MainForm.pas' {FrmSiservService};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFrmSiservService, FrmSiservService);
  Application.Run;
end.
