Attribute VB_Name = "DeclareFun"
'VB中的整型数据为16位
'USB
Public Declare Function dsoHTSearchDevice Lib "HTHardDll.dll" (DevInfo As Integer) As Integer
Public Declare Function dsoSetUSBBus Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer) As Boolean
Public Declare Function dsoHTReadCalibrationData Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, pLevel As Integer, ByVal nLen As Integer) As Integer
Public Declare Function dsoHTSetSampleRate Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, ByVal nTimeDIV As Integer, ByVal nYTFormat As Integer) As Integer
'Public Declare Function dsoHTSetCHAndTrigger Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, ByRef rcRelayControl As RelayControl) As Integer
Public Declare Function dsoHTSetCHAndTriggerVB Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, bCHEnable As Integer, CHVoltDIV As Integer, CHCoupling As Integer, CHBWLimit As Integer, ByVal nTriggerSource As Integer, ByVal nTriggerFilt As Integer, ByVal nALT As Integer) As Integer
Public Declare Function dsoHTSetTriggerAndSyncOutput Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, ByVal nSynMode As Integer, ByVal nlaTriggerMode As Integer, ByVal nTriggerMode As Integer, ByVal nTriggerSlope As Integer, ByVal nPWCondition As Integer, ByVal nPW As Long, ByVal nVideoStandard As Integer, ByVal nVedioSyncSelect As Integer, ByVal nVideoHsyncNumOption As Integer, ByVal nSync As Integer) As Integer

Public Declare Function dsoHTSetCHPos Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, pLevel As Integer, ByVal nVoltDIV As Integer, ByVal nPos As Integer, ByVal nCH As Integer) As Integer

Public Declare Function dsoHTSetVTriggerLevel Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, pLevel As Integer, ByVal nPos As Integer) As Integer
Public Declare Function dsoHTSetHTriggerLength Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, ByVal nBufferLen As Integer, ByVal HTriggerPos As Integer, ByVal nTimeDIV As Integer, ByVal nYTFormat As Integer) As Integer
Public Declare Function dsoHTStartCollectData Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer) As Integer
Public Declare Function dsoHTStartTrigger Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer) As Integer
Public Declare Function dsoHTForceTrigger Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer) As Integer
Public Declare Function dsoHTGetState Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer) As Integer
Public Declare Function dsoHTGetData Lib "HTHardDll.dll" (ByVal nDeviceInder As Long, CH1Data As Integer, CH2Data As Integer, CH3Data As Integer, CH4Data As Integer, ByRef CONTROLDATA As CONTROLDATA) As Integer

Public Declare Function laSetTrigSource Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, ByVal nSour As Integer) As Boolean
Public Declare Function laSetVoltDiv Lib "HTHardDll.dll" (ByVal nDeviceIndex As Integer, nlaVoltDiv As Integer) As Boolean
'Public Declare Function dsoGetDisplayDataFromSourceData Lib "HTHardDll.dll" (pDisplayData() As Integer, pSourceData() As Integer, LeverPos As Integer, ByVal nCHCount As Integer, ByVal nDatalen As Long) As Boolean
Public Declare Function dsoGetDisplayDataFromSourceDataSingle Lib "HTHardDll.dll" (pDisplayData As Integer, pSourceData As Integer, LeverPos As Integer, ByVal nDatalen As Long, ByVal nCH As Integer) As Boolean
'Draw
Public Declare Function HTDrawGrid Lib "HTDisplayDll.dll" (ByVal hDC As Long, ByVal nLeft As Long, ByVal nTop As Long, ByVal nRight As Long, ByVal nBottom As Long, ByVal nHoriGridNum As Long, ByVal nVertGridNum As Long, ByVal nBright As Long, ByVal IsGrid As Long) As Long
Public Declare Function HTDrawWaveInYTVB Lib "HTDisplayDll.dll" (ByVal hDC As Long, ByVal Left As Long, ByVal Top As Long, ByVal Right As Long, ByVal Bottom As Long, ByVal R As Integer, ByVal G As Integer, ByVal B As Integer, ByVal nDisTye As Integer, pData As Integer, ByVal nLen As Long, ByVal nDisLen As Long, ByVal CenterData As Long, ByVal nDisLeverPos As Integer, ByVal Horizontal As Double, ByVal Vertical As Double, ByVal YTFormat As Integer, ByVal AlreadLen As Long, ByVal nCH As Integer) As Long

'Soft
Public Declare Function dsoGetBufferDataByInsertData Lib "HTSoftDll.dll" (SourceData As Integer, BufferData As Integer, ByVal nCH As Integer, ByRef stControl As CONTROLDATA, ByVal nInsertMode As Integer) As Boolean

Public Declare Function dsoGetlaBufferDataByInsertData Lib "HTSoftDll.dll" (SourceData As Integer, BufferData As Integer, ByVal nCH As Integer, ByRef stControl As CONTROLDATA) As Boolean

Public Declare Function dsoSFFindTrigger Lib "HTSoftDll.dll" (SourceData As Integer, BufferData As Integer, ByRef stControl As CONTROLDATA) As Long

Public Declare Function dsoGetSoftTriggerPos Lib "HTSoftDll.dll" (ByVal nTimeDIV As Integer, ByVal nTriggerSource As Integer, pState As Long) As Boolean

Public Declare Function dsoSFFindTriggerCopy Lib "HTSoftDll.dll" (SourceData As Integer, BufferData As Integer, ByRef stControl As CONTROLDATA, ByVal TriggerPoint As Long) As Integer
