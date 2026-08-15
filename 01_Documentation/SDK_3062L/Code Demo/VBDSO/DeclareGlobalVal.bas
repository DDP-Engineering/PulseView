Attribute VB_Name = "DeclareGlobalVal"
Type RelayControl
    bCHEnable(3) As Integer
    nCHVoltDIV(3) As Integer
    nCHCoupling(3) As Integer
    bCHBWLimit(3) As Integer
    nTrigSource As Integer
    bTrigFilt As Integer
    nALT As Integer
End Type

Type CONTROLDATA
        
    nCHSet As Integer
    nTimeDIV As Integer
    nTriggerSource As Integer
    nHTriggerPos As Integer
    nVTriggerPos As Integer
    nTriggerSlope As Integer
    nBufferLen As Long
    nReadDataLen As Long
    nAlreadyReadLen As Long
    nALT As Integer
    nETSOpen As Integer
End Type

Type COLORREF
    R As Integer
    G As Integer
    B As Integer
End Type

Type RECT
    Left As Integer
    Top As Integer
    Right As Integer
    Bottom As Integer
End Type
'''''''''''''
Public MAX_CH_TOTAL As Integer
Public MAX_CH_NUM As Integer
Public MAX_DATA As Integer
Public m_nDeviceNum As Integer
Public m_nDeviceIndex As Integer
Public m_pSrcData_CH1(10239) As Integer
Public m_pSrcData_CH2(10239) As Integer
Public m_pSrcData_D01(10239) As Integer
Public m_pSrcData_D02(10239) As Integer
Public m_pSrcData_D03(10239) As Integer
Public m_pSrcData_D04(10239) As Integer
Public m_pSrcData_D05(10239) As Integer
Public m_pSrcData_D06(10239) As Integer
Public m_pSrcData_D07(10239) As Integer
Public m_pSrcData_D08(10239) As Integer
Public m_pSrcData_D09(10239) As Integer
Public m_pSrcData_D10(10239) As Integer
Public m_pSrcData_D11(10239) As Integer
Public m_pSrcData_D12(10239) As Integer
Public m_pSrcData_D13(10239) As Integer
Public m_pSrcData_D14(10239) As Integer
Public m_pSrcData_D15(10239) As Integer
Public m_pSrcData_D16(10239) As Integer
Public CH1SrcData(10239) As Integer
Public CH2SrcData(10239) As Integer
Public CH3SrcData(10239) As Integer
Public CH4SrcData(10239) As Integer
Public m_clrRGB(17) As COLORREF
Public m_nCalLevel(71) As Integer
Public m_nCurCH As Integer        '触发源设定
Public m_nTimeDIV As Integer
Public m_nYTFormat As Integer
Public m_stControl As CONTROLDATA
Public rcRelayControl As RelayControl
Public m_nSynMode As Integer
Public m_nlaTrigMode As Integer
Public m_nTriggerMode As Integer
Public m_nTriggerSweep As Integer
Public m_nTriggerSlope As Integer
Public m_nInsertMode As Integer
Public m_nLeverPos(17) As Integer
Public m_nReadOK As Integer
Public m_nlaVoltDiv(15) As Integer
Public ForceTriggerCnt As Integer
Public m_nDisLen As Long
Public m_nDisType As Long
Public m_nAutoTriggerCnt As Integer
Public m_bStartNew As Boolean
