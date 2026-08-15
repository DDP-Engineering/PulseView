Attribute VB_Name = "Start"
Sub Main()
     Dim DevInfo(63) As Integer
     Dim result As Integer
     
    
    InitializeVariables

    m_nDeviceNum = dsoHTSearchDevice(DevInfo(0))

    If m_nDeviceNum = 0 Then
         MsgBox ("DSO not found!")
         End
     End If

     InitHard
     MainForm.Visible = True

     MainForm.GetDataLoop.Enabled = True
    
End Sub

Public Sub InitializeVariables()
Dim i As Long
    i = 0
    MAX_CH_NUM = 4
    MAX_CH_TOTAL = 18
    MAX_DATA = 255
    m_nDeviceNum = 0
    m_nDeviceIndex = 0
    m_clrRGB(0).R = 255
    m_clrRGB(0).G = 255
    m_clrRGB(0).B = 0
    m_clrRGB(1).R = 0
    m_clrRGB(1).G = 255
    m_clrRGB(1).B = 255
    For i = 0 To 71
        m_nCalLevel(i) = 0
    Next i
    m_nCurCH = 0    'Ä¬ÈÏCH1£¬¿ÉÈ¡1~17
    m_nTimeDIV = 6
    m_nYTFormat = 0
    m_nInsertMode = 2
    For i = 0 To 3
        rcRelayControl.bCHEnable(i) = 1
        rcRelayControl.nCHVoltDIV(i) = 6
        rcRelayControl.nCHCoupling(i) = 1
        rcRelayControl.bCHBWLimit(i) = 0
    Next i
    rcRelayControl.nTrigSource = m_nCurCH
    rcRelayControl.bTrigFilt = 0
    rcRelayControl.nALT = 0
    m_nSynMode = 0  '0x00
    m_nlaTrigMode = 0
    
    m_nTriggerMode = 0
    m_nTriggerSlope = 0
    m_nTriggerSweep = 0
    m_nLeverPos(0) = 115
    m_nLeverPos(1) = 130
    For i = 2 To MAX_CH_TOTAL - 1
        If i < 10 Then
            m_nLeverPos(i) = 0 + i * 12
        Else

            m_nLeverPos(i) = 45 + i * 12
        End If
        m_clrRGB(i).R = 0
        m_clrRGB(i).G = 255
        m_clrRGB(i).B = 0
    Next i
    m_stControl.nCHSet = 15
    m_stControl.nTimeDIV = m_nTimeDIV
    m_stControl.nTriggerSource = m_nCurCH
    m_stControl.nHTriggerPos = 50
    m_stControl.nVTriggerPos = m_nLeverPos(m_nCurCH)
    m_stControl.nTriggerSlope = 0
    m_stControl.nBufferLen = 10240
    m_stControl.nReadDataLen = 10240
    m_stControl.nAlreadyReadLen = 10240
    m_stControl.nALT = 0
    
    
    For i = 0 To MAX_CH_TOTAL - 2 - 1
       m_nlaVoltDiv(i) = 58
    Next i
    
    ReadOK = 0
    m_nAutoTriggerCnt = 0
    m_bStartNew = True
    m_nDisType = 0
    m_nDisLen = 10000
End Sub


Public Sub InitHard()
    Dim i As Integer
    Dim result As Integer
    Dim bstate As Boolean
    
    m_nDeviceIndex = 0
    result = dsoSetUSBBus(m_nDeviceIndex)
    result = dsoHTReadCalibrationData(m_nDeviceIndex, m_nCalLevel(0), 72)
    result = dsoHTSetSampleRate(m_nDeviceIndex, m_nTimeDIV, m_nYTFormat)
    result = dsoHTSetCHAndTriggerVB(DeviceIndex, rcRelayControl.bCHEnable(0), rcRelayControl.nCHVoltDIV(0), rcRelayControl.nCHCoupling(0), rcRelayControl.bCHBWLimit(0), rcRelayControl.nTrigSource, rcRelayControl.bTrigFilt, rcRelayControl.nALT)

    If rcRelayControl.nTrigSource < 2 Or rcRelayControl.nTrigSource = 18 Then
        m_nSynMode = 0
        result = dsoHTSetTriggerAndSyncOutput(m_nDeviceIndex, m_nSynMode, m_nlaTrigMode, m_nTriggerMode, m_nTriggerSlope, 0, 0, 0, 0, 1, 0)
    Else
        m_nSynMode = 5 '0x05
        m_nlaTrigMode = 0
        result = dsoHTSetTriggerAndSyncOutput(m_nDeviceIndex, m_nSynMode, m_nlaTrigMode, m_nTriggerMode, m_nTriggerSlope, 0, 0, 0, 0, 1, 0)
        bstate = laSetTrigSource(m_nDeviceIndex, rcRelayControl.nTrigSource - 2)
    End If
    For i = 0 To MAX_CH_NUM - 2 - 1
        result = dsoHTSetCHPos(m_nDeviceIndex, m_nCalLevel(0), rcRelayControl.nCHVoltDIV(i), MAX_DATA - m_nLeverPos(i), i)
    Next i
    result = dsoHTSetVTriggerLevel(m_nDeviceIndex, m_nCalLevel(0), MAX_DATA - m_nLeverPos(rcRelayControl.nTrigSource))
    result = dsoHTSetHTriggerLength(m_nDeviceIndex, m_stControl.nBufferLen, m_stControl.nHTriggerPos, m_nTimeDIV, m_nYTFormat)

   bstate = laSetVoltDiv(m_nDeviceIndex, m_nlaVoltDiv(0))
End Sub
Public Sub CollectData()
    Dim nState As Integer

    If m_bStartNew Then
        dsoHTStartCollectData (m_nDeviceIndex)
        dsoHTStartTrigger (m_nDeviceIndex)

        m_nAutoTriggerCnt = 0
        m_bStartNew = False
    End If
    nState = dsoHTGetState(m_nDeviceIndex)
    If nState = 1 Then
        If m_nTriggerSweep = 0 Then

            dsoHTStartTrigger (m_nDeviceIndex)

            m_nAutoTriggerCnt = m_nAutoTriggerCnt + 1
            If m_nAutoTriggerCnt > 5 Then

                dsoHTForceTrigger (m_nDeviceIndex)
                m_nAutoTriggerCnt = 0
             End If
        End If
    Else
        If nState = 3 Then
        
        Else
            If nState = 7 Then
                ReadData
                m_bStartNew = True
                m_nAutoTriggerCnt = 0
            End If
        End If
    End If
End Sub
Public Sub ReadData()
    Dim i, j, result As Integer
    Dim bstate As Boolean
    Dim pReadData_CH1(10239) As Integer
    Dim pReadData_CH2(10239) As Integer
    Dim pReadData_CH3(10239) As Integer
    Dim pReadData_CH4(10239) As Integer
    Dim nData_CH1(10239) As Integer
    Dim nData_CH2(10239) As Integer
    Dim nData_CH3(10239) As Integer
    Dim nData_CH4(10239) As Integer
    If m_stControl.nTimeDIV > 9 Then
        m_nReadOK = dsoHTGetData(m_nDeviceIndex, pReadData_CH1(0), pReadData_CH2(0), pReadData_CH3(0), pReadData_CH4(0), m_stControl)
    Else
        m_nReadOK = dsoHTGetData(m_nDeviceIndex, nData_CH1(0), nData_CH2(0), nData_CH3(0), nData_CH4(0), m_stControl)
        If m_stControl.nTimeDIV > 7 Then
            If rcRelayControl.bCHEnable(0) = 1 Then
                Call dsoGetBufferDataByInsertData(nData_CH1(0), pReadData_CH1(0), 0, m_stControl, m_nInsertMode)
            End If
            If rcRelayControl.bCHEnable(1) = 1 Then
                result = dsoGetBufferDataByInsertData(nData_CH2(0), pReadData_CH2(0), 1, m_stControl, m_nInsertMode)
            End If
            If rcRelayControl.bCHEnable(2) = 1 Then
                result = dsoGetlaBufferDataByInsertData(nData_CH3(0), pReadData_CH3(0), 2, m_stControl)
            End If
            If rcRelayControl.bCHEnable(3) = 1 Then
                result = dsoGetlaBufferDataByInsertData(nData_CH4(0), pReadData_CH4(0), 3, m_stControl)
            End If
        Else
            Dim nState(17) As Long
            Dim nDataBuffer(40959) As Integer
            If m_stControl.nTriggerSource < MAX_CH_TOTAL Then
                Dim nSrc As Integer
                nSrc = 0
                If m_stControl.nTriggerSource > 3 Then
                    nSrc = 0
                Else
                    nSrc = m_stControl.nTriggerSource
                End If
                For i = 0 To MAX_CH_NUM - 1
                    If i < 2 Then
                        Select Case nSrc
                            Case Is = 0
                                bstate = dsoGetBufferDataByInsertData(nData_CH1(0), nDataBuffer(0), nSrc, m_stControl, m_nInsertMode)
                            Case Is = 0
                                bstate = dsoGetBufferDataByInsertData(nData_CH2(0), nDataBuffer(0), nSrc, m_stControl, m_nInsertMode)
                            Case Is = 0
                                bstate = dsoGetBufferDataByInsertData(nData_CH3(0), nDataBuffer(0), nSrc, m_stControl, m_nInsertMode)
                            Case Is = 0
                                bstate = dsoGetBufferDataByInsertData(nData_CH4(0), nDataBuffer(0), nSrc, m_stControl, m_nInsertMode)
                        End Select
                        If i = 0 Then
                            nState(i) = dsoSFFindTrigger(nDataBuffer(0), pReadData_CH1(0), m_stControl)
                        Else
                            nState(i) = dsoSFFindTrigger(nDataBuffer(0), pReadData_CH2(0), m_stControl)
                        End If
                        Call dsoGetSoftTriggerPos(m_stControl.nTimeDIV, i, nState(0))
                        If m_stControl.nTriggerSource <> i Then
                            If i = 0 And rcRelayControl.bCHEnable(0) = 1 Then
                                bstate = dsoGetBufferDataByInsertData(nData_CH1(0), nDataBuffer(0), 0, m_stControl, m_nInsertMode)
                                Call dsoSFFindTriggerCopy(nDataBuffer(0), pReadData_CH1(0), m_stControl, nState(0))
                            End If
                            If i = 1 And rcRelayControl.bCHEnable(1) = 1 Then
                                bstate = dsoGetBufferDataByInsertData(nData_CH2(0), nDataBuffer(0), 1, m_stControl, m_nInsertMode)
                                result = dsoSFFindTriggerCopy(nDataBuffer(0), pReadData_CH2(0), m_stControl, nState(1))
                            End If
                        End If
                    Else
                            If i = 2 And rcRelayControl.bCHEnable(2) = 1 Then
                                result = dsoGetlaBufferDataByInsertData(nData_CH3(0), pReadData_CH3(0), 2, m_stControl)
                            End If
                            If i = 3 And rcRelayControl.bCHEnable(3) = 1 Then
                                result = dsoGetlaBufferDataByInsertData(nData_CH4(0), pReadData_CH4(0), 3, m_stControl)
                            End If
                    End If
                Next i
            End If
       End If
    End If
    If m_nReadOK = 1 Then

        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_CH1(0), pReadData_CH1(0), m_nLeverPos(0), m_stControl.nReadDataLen, 0)  'CH1
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_CH2(0), pReadData_CH2(0), m_nLeverPos(0), m_stControl.nReadDataLen, 1)  'CH2

        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D01(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 2)  'D01
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D02(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 3)  'D02
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D03(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 4)  'D03
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D04(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 5)  'D04
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D05(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 6)  'D05
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D06(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 7)  'D06
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D07(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 8)  'D07
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D08(0), pReadData_CH3(0), m_nLeverPos(0), m_stControl.nReadDataLen, 9)  'D08

        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D09(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 10)  'D09
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D10(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 11)  'D10
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D11(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 12)  'D11
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D12(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 13)  'D12
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D13(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 14)  'D13
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D14(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 15)  'D14
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D15(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 16)  'D15
        bstate = dsoGetDisplayDataFromSourceDataSingle(m_pSrcData_D16(0), pReadData_CH4(0), m_nLeverPos(0), m_stControl.nReadDataLen, 17)  'D16
    
    End If
    
End Sub



























