# SiservService

Grupo de projetos Delphi para consulta e baixa automática de títulos TAC EFrete/NSTech.

- `SiservService.dproj`: DLL que executa o processo e exporta `ExecutarProcesso`.
- `SiservServiceUI.dproj`: interface VCL com execução manual e timer.
- `SiservService.ini`: intervalo, ativação, período de consulta e arquivo de log.

O DLL utiliza o `ServiceDataModule.pas` local, sem `DMConnec.pas`, `TAC.pas` ou `TAC.dfm`. O processamento foi copiado para `ServiceTAC.pas`. A conexão Firebird e o usuário do sistema são configurados na seção `[Banco]` do `SiservService.ini`.

Compile primeiro o DLL e depois o EXE. Distribua juntos `SiservServiceUI.exe`, `SiservService.dll`, `SiservService.ini` e as DLLs/runtime/dependências já exigidas pelo Siserv.
