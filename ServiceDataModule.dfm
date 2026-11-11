object ServiceDataModule: TServiceDataModule
  OldCreateOrder = False
  OnCreate = DataModuleCreate
  Height = 240
  Width = 320
  object Transaction: TIBCTransaction
    DefaultConnection = DBConnec
    Left = 32
    Top = 88
  end
  object DBConnec: TIBCConnection
    Options.EnableMemos = True
    Options.DisconnectedMode = True
    Options.EnableBCD = True
    Options.EnableFMTBCD = True
    DefaultTransaction = Transaction
    Port = '3050'
    Pooling = True
    AutoCommit = False
    LoginPrompt = False
    Left = 32
    Top = 32
  end
end
