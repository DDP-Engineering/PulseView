// Hard.h: interface for the CHard class.
//
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_HARD_H__9C4B6FA6_38DA_46DD_84A9_790E05FFA5C4__INCLUDED_)
#define AFX_HARD_H__9C4B6FA6_38DA_46DD_84A9_790E05FFA5C4__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

class CHard  
{
public:
	CHard();
	virtual ~CHard();
//Attributes
public:
	USHORT m_nDeviceIndex;
	USHORT m_nCurCH;		// 触发源设定
	USHORT m_nDeviceNum;
	short* m_pSrcData[MAX_CH_TOTAL];//读取的数据减去零电平的位置(-255 ~ 255)
	USHORT m_nCalLevel[CAL_LEVEL_LEN];//Cal Level
	USHORT m_nTimeDIV;
	USHORT m_nYTFormat;
	CONTROLDATA m_stControl;
	RELAYCONTROL RelayControl;
	USHORT m_nSynMode;
	USHORT m_nlaTrigMode;
	USHORT m_nTriggerMode;
	USHORT m_nTriggerSweep;
	USHORT m_nTriggerSlope;
	USHORT m_nInsertMode;
	USHORT m_nLeverPos[MAX_CH_TOTAL];
	COLORREF m_clrRGB[MAX_CH_TOTAL];
	//
	USHORT m_nReadOK;//本次读数据是否正确,0,不正确；非0不正确。

	//LA 部分
	USHORT m_nlaVoltDiv[MAX_CH_TOTAL- 2];		//16个逻辑通道
//Operations
public:
	void Init();
	void ReadData();
//	void SourceToDisplay(USHORT* pData,ULONG nDataLen,USHORT nCH);
//	//LA部分
//	float Cal(float nVal,int index);
//	void LaSourceToDisplay(USHORT *pData, ULONG nDataLen, int nCH);
//	void laInsertData(USHORT *nData, USHORT *pReadData, ULONG i,CONTROLDATA *pControl);
//	void ProcessInsertData(WORD* SourceData,WORD* BufferData,USHORT nCH);
};

#endif // !defined(AFX_HARD_H__9C4B6FA6_38DA_46DD_84A9_790E05FFA5C4__INCLUDED_)
