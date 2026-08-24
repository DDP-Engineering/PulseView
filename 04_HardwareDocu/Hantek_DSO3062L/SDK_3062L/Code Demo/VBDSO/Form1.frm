VERSION 5.00
Begin VB.Form MainForm 
   BorderStyle     =   3  'Fixed Dialog
   Caption         =   "VB6.0 SDK for DSO"
   ClientHeight    =   6825
   ClientLeft      =   45
   ClientTop       =   435
   ClientWidth     =   10590
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   6825
   ScaleWidth      =   10590
   ShowInTaskbar   =   0   'False
   StartUpPosition =   2  'CenterScreen
   Begin VB.Timer GetDataLoop 
      Interval        =   50
      Left            =   9360
      Top             =   5880
   End
   Begin VB.PictureBox BackPicture 
      BackColor       =   &H80000001&
      BeginProperty Font 
         Name            =   "ËÎÌו"
         Size            =   9
         Charset         =   134
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   6840
      Left            =   0
      ScaleHeight     =   6780
      ScaleWidth      =   10560
      TabIndex        =   0
      Top             =   0
      Width           =   10620
      Begin VB.PictureBox DisplayPicture 
         AutoRedraw      =   -1  'True
         BackColor       =   &H80000008&
         Height          =   6375
         Left            =   120
         ScaleHeight     =   421
         ScaleMode       =   3  'Pixel
         ScaleWidth      =   677
         TabIndex        =   1
         Top             =   120
         Width           =   10215
      End
   End
End
Attribute VB_Name = "MainForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Private Sub GetDataLoop_Timer()
    DrawGrid
    CollectData
    Call DrawWave(m_pSrcData_CH1(0), 0)
    Call DrawWave(m_pSrcData_CH2(0), 1)
    Call DrawWave(m_pSrcData_D01(0), 2)
    Call DrawWave(m_pSrcData_D02(0), 3)
    Call DrawWave(m_pSrcData_D03(0), 4)
    Call DrawWave(m_pSrcData_D04(0), 5)
    Call DrawWave(m_pSrcData_D05(0), 6)
    Call DrawWave(m_pSrcData_D06(0), 7)
    Call DrawWave(m_pSrcData_D07(0), 8)
    Call DrawWave(m_pSrcData_D08(0), 9)
    Call DrawWave(m_pSrcData_D09(0), 10)
    Call DrawWave(m_pSrcData_D10(0), 11)
    Call DrawWave(m_pSrcData_D11(0), 12)
    Call DrawWave(m_pSrcData_D12(0), 13)
    Call DrawWave(m_pSrcData_D13(0), 14)
    Call DrawWave(m_pSrcData_D14(0), 15)
    Call DrawWave(m_pSrcData_D15(0), 16)
    Call DrawWave(m_pSrcData_D16(0), 17)
End Sub

Public Sub DrawGrid()
    Dim result As Long
    MainForm.DisplayPicture.Cls
    result = HTDrawGrid(MainForm.DisplayPicture.hDC, 15, 15, MainForm.DisplayPicture.ScaleWidth - 15, MainForm.DisplayPicture.ScaleHeight - 15, 10, 8, 200, 1)
End Sub
Public Sub DrawWave(pData As Integer, ByVal nCH As Integer)
    Dim Grid As RECT
    Dim i As Integer
    Grid.Left = 15
    Grid.Top = 15
    Grid.Right = MainForm.DisplayPicture.ScaleWidth - 15
    Grid.Bottom = MainForm.DisplayPicture.ScaleHeight - 15

    result = HTDrawWaveInYTVB(MainForm.DisplayPicture.hDC, Grid.Left, Grid.Top, Grid.Right, Grid.Bottom, m_clrRGB(nCH).R, m_clrRGB(nCH).G, m_clrRGB(nCH).B, m_nDisType, pData, m_stControl.nReadDataLen, m_nDisLen, m_stControl.nReadDataLen / 2, m_nLeverPos(nCH), 1#, 1#, 0, m_stControl.nAlreadyReadLen, nCH)

End Sub

