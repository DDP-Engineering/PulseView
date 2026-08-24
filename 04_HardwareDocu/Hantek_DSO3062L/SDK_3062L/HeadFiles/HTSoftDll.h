#ifndef _HT_SOFT_DLL_H
#define _HT_SOFT_DLL_H

#ifndef DLL_API
#define DLL_API extern "C" _declspec(dllimport)
#endif
#define WINAPI __stdcall
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

DLL_API ULONG WINAPI dsoSFFindTrigger(WORD* SourceData,WORD* BufferData,PCONTROLDATA Control);

DLL_API WORD WINAPI dsoSFFindTriggerCopy(WORD* SourceData,WORD* BufferData,PCONTROLDATA Control,ULONG TriggerPoint);

DLL_API void WINAPI dsoGetSoftTriggerPos(USHORT nTimeDIV,USHORT nTriggerSource,ULONG* pState);

DLL_API void WINAPI dsoGetBufferDataByInsertData(WORD *SourceData,WORD *BufferData,WORD nCH,PCONTROLDATA pControl,WORD nInsertMode);

DLL_API void WINAPI dsoGetlaBufferDataByInsertData(USHORT *SourceData, USHORT *BufferData, ULONG i,PCONTROLDATA pControl);


#endif
