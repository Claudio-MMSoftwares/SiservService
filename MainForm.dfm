object FrmSiservService: TFrmSiservService
  Left = 0
  Top = 0
  Caption = 'Siserv Service'
  ClientHeight = 380
  ClientWidth = 700
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = True
  PixelsPerInch = 96
  TextHeight = 13
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 700
    Height = 57
    Align = alTop
    TabOrder = 0
    object StatusLabel: TLabel
      Left = 10
      Top = 5
      Width = 63
      Height = 13
      Caption = 'Aguardando.'
    end
    object ExecutarButton: TButton
      Left = 10
      Top = 26
      Width = 150
      Height = 25
      Caption = 'Executar agora'
      TabOrder = 0
    end
  end
  object LogMemo: TMemo
    Left = 0
    Top = 57
    Width = 700
    Height = 323
    Align = alClient
    ScrollBars = ssVertical
    TabOrder = 1
  end
end
