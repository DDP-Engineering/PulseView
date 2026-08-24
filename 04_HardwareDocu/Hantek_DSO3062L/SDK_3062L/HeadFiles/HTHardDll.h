#ifndef _HT_HARD_DLL_H
#define _HT_HARD_DLL_H

#ifndef DLL_API
#define DLL_API extern "C" __declspec(dllimport)
#endif
#define WIN_API __stdcall

typedef struct _HT_RELAY_CONTROL
{
	BOOL bCHEnable[4];
	WORD nCHVoltDIV[4];
	WORD nCHCoupling[4];
	BOOL bCHBWLimit[4];
	WORD nTrigSource;
	BOOL bTrigFilt;
	WORD nALT;
}RELAYCONTROL,*PRELAYCONTROL;

#ifndef struct_HT_CONTROL_DATA
#define struct_HT_CONTROL_DATA
typedef struct _HT_CONTROL_DATA
{
		WORD nCHSet;
        WORD nTimeDIV;
        WORD nTriggerSource;
        WORD nHTriggerPos;
		WORD nVTriggerPos;
		WORD nTriggerSlope;
		ULONG nBufferLen;
		ULONG nReadDataLen;
		ULONG nAlreadyReadLen;
    	WORD nALT;
		WORD nETSOpen;
		
}CONTROLDATA,*PCONTROLDATA;
#endif

DLL_API WORD WINAPI dsoHTSearchDevice(short* pDevInfo);

DLL_API WORD WINAPI dsoSetUSBBus(WORD nDeviceIndex);

DLL_API WORD WINAPI dsoHTReadCalibrationData(WORD nDeviceIndex,WORD* pLevel,WORD nLen);

DLL_API WORD WINAPI dsoHTSetCHPos(WORD nDeviceIndex,WORD* pLevel,WORD nVoltDIV,WORD nPos,WORD nCH);

DLL_API WORD WINAPI dsoHTSetVTriggerLevel(WORD nDeviceIndex,WORD* pLevel,WORD nPos);

DLL_API WORD WINAPI dsoHTSetHTriggerLength(WORD nDeviceIndex,ULONG nBufferLen,WORD HTriggerPos,WORD nTimeDIV,WORD nYTFormat);

DLL_API WORD WINAPI dsoHTSetCHAndTrigger(WORD nDeviceIndex,RELAYCONTROL RelayControl);

DLL_API WORD WINAPI dsoHTSetCHAndTriggerVB(WORD nDeviceIndex,WORD* pCHEnable,WORD* pCHVoltDIV,WORD* pCHCoupling,WORD* pCHBWLimit,WORD nTriggerSource,WORD nTriggerFilt,WORD nALT);

DLL_API WORD WINAPI dsoHTSetTriggerAndSyncOutput(WORD nDeviceIndex,WORD nSynMode,WORD nlaTriggerMode,WORD nTriggerMode,WORD nTriggerSlope,WORD nPWCondition,ULONG nPW,USHORT nVideoStandard,USHORT nVedioSyncSelect,USHORT nVideoHsyncNumOption,WORD nSync);

DLL_API WORD WINAPI dsoHTSetSampleRate(WORD nDeviceIndex,WORD nTimeDIV,WORD nYTFormat);

DLL_API WORD WINAPI dsoHTStartCollectData(WORD nDeviceIndex);

DLL_API WORD WINAPI dsoHTStartTrigger(WORD nDeviceIndex);

DLL_API WORD WINAPI dsoHTForceTrigger(WORD nDeviceIndex);

DLL_API WORD WINAPI dsoHTGetState(WORD nDeviceIndex);

DLL_API WORD WINAPI dsoHTGetData(WORD nDeviceIndex,WORD* pCH1Data,WORD* pCH2Data,WORD* pCH3Data,WORD* pCH4Data,PCONTROLDATA pControl);

//-----------LA-----------------
DLL_API BOOL WINAPI laSetTrigSource(WORD DeviceIndex,unsigned char nSour);
DLL_API BOOL WINAPI laSetVoltDiv(WORD DeviceIndex,WORD *nlaVoltDiv);
DLL_API BOOL WINAPI dsoGetDisplayDataFromSourceDataSingle(short *pDisplayData,WORD *pSourceData,WORD *LeverPos,ULONG nDataLen,WORD nCH);
//-----------DDS--------------
DLL_API ULONG WINAPI ddsSetOnOff(WORD DeviceIndex,short nOnOff);
DLL_API ULONG WINAPI ddsSetFrequency(WORD DeviceIndex,double dbFre,WORD* pWaveNum,WORD* pPeriodNum);
DLL_API ULONG WINAPI ddsDownload(WORD DeviceIndex,WORD iWaveNum, WORD* pData);
DLL_API ULONG WINAPI ddsSetSyncOut(WORD DeviceIndex, BOOL bEnable);
DLL_API ULONG WINAPI ddsSetCmd(WORD DeviceIndex, USHORT nSingle);
//DLL_API ULONG WINAPI ddsSetPowerOn(WORD DeviceIndex,BOOL bEnable);

// -------------------------------







//

#endif

