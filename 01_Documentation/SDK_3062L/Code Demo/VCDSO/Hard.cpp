// Hard.cpp: implementation of the CHard class.
//
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "VCDSO.h"
#include "Hard.h"

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[]=__FILE__;
#define new DEBUG_NEW
#endif

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CHard::CHard()
{
	ULONG i = 0;
	m_nDeviceIndex = 0;
	m_nDeviceNum = 0;
	for(i=0;i<MAX_CH_TOTAL;i++)
	{
		m_pSrcData[i] = new short[BUF_10K_LEN];
	}
	m_clrRGB[CH1] = RGB(255,255,0);
	m_clrRGB[CH2] = RGB(0,255,255);
	memset(m_nCalLevel,0,sizeof(m_nCalLevel));
	m_nCurCH = CH1;//D0;		//触发通道
	m_nTimeDIV = 12;	//50us
//	m_nTimeDIV = 9;		//时基5us
//	m_nTimeDIV = 6;		//时基200ns
//	m_nTimeDIV = 1;		//时基10ns

	m_nYTFormat = 0;
	m_nInsertMode = 2;
	for(i=0;i<MAX_CH_NUM;i++)
	{
		RelayControl.bCHEnable[i] = 1;
		RelayControl.nCHVoltDIV[i] = 6;
		RelayControl.nCHCoupling[i] = AC;
		RelayControl.bCHBWLimit[i] = 0;
	}	
	RelayControl.nTrigSource = m_nCurCH;
	RelayControl.bTrigFilt = 0;
	RelayControl.nALT = 0;
	m_nSynMode = 0x00;		//0x000 示波器；0x101 逻辑分析仪；
	m_nlaTrigMode = 0;		//取值0、1、2
	m_nTriggerMode = EDGE;
	m_nTriggerSlope = RISE;
	m_nTriggerSweep = AUTO;
	m_nLeverPos[CH1] = 115;
	m_nLeverPos[CH2] = 130;
	for(i=2;i<MAX_CH_TOTAL;i++)
	{
		if(i<10)
		{
			m_nLeverPos[i]=(USHORT)(0+i*12);
		}
		else
		{
			m_nLeverPos[i]=(USHORT)(45+i*12);
		}
		m_clrRGB[i] = RGB(0,255,0);
	}
	m_stControl.nTriggerSource = m_nCurCH;
	m_stControl.nCHSet = 0x0F;////Factory Setup
	m_stControl.nTimeDIV = m_nTimeDIV;//Factory Setup
	m_stControl.nHTriggerPos = 50;//Factory Setup
	m_stControl.nVTriggerPos = m_nLeverPos[m_nCurCH];//Factory Setup
	m_stControl.nTriggerSlope = RISE;//Factory Setup
	m_stControl.nBufferLen = BUF_10K_LEN;//Factory Setup
	m_stControl.nReadDataLen = BUF_10K_LEN;//Factory Setup
	m_stControl.nAlreadyReadLen = BUF_10K_LEN;//Factory Setup
	m_stControl.nALT = 0;//Factory Setup
	m_nReadOK = 0;
}

CHard::~CHard()
{
	int i;
	for(i=0;i<MAX_CH_TOTAL;i++)
	{
		delete []m_pSrcData[i];
	}
}

void CHard::Init()
{
	int i ;
	m_nDeviceIndex = 0;
	dsoSetUSBBus(m_nDeviceIndex);
	dsoHTReadCalibrationData(m_nDeviceIndex,m_nCalLevel,CAL_LEVEL_LEN);
	dsoHTSetSampleRate(m_nDeviceIndex,m_nTimeDIV,m_nYTFormat);
	dsoHTSetCHAndTrigger(m_nDeviceIndex,RelayControl);

	if(RelayControl.nTrigSource<2||RelayControl.nTrigSource==18)
	{
		m_nSynMode=0;
		dsoHTSetTriggerAndSyncOutput(m_nDeviceIndex,m_nSynMode,m_nlaTrigMode,m_nTriggerMode,m_nTriggerSlope,0,0,0,0,1,0);
	}
	else
	{
		m_nSynMode=0x05;
		m_nlaTrigMode=0;
		dsoHTSetTriggerAndSyncOutput(m_nDeviceIndex,m_nSynMode,m_nlaTrigMode,m_nTriggerMode,m_nTriggerSlope,0,0,0,0,1,0);		
		laSetTrigSource(m_nDeviceIndex,RelayControl.nTrigSource-2);
	}
	for(i =0;i<MAX_CH_NUM-2;i++)
	{
		dsoHTSetCHPos(m_nDeviceIndex,m_nCalLevel,RelayControl.nCHVoltDIV[i],MAX_DATA-m_nLeverPos[i],i);
	}
	dsoHTSetVTriggerLevel(m_nDeviceIndex,m_nCalLevel,MAX_DATA-m_nLeverPos[RelayControl.nTrigSource]);
	dsoHTSetHTriggerLength(m_nDeviceIndex,m_stControl.nBufferLen,m_stControl.nHTriggerPos,m_nTimeDIV,m_nYTFormat);	
	
	for(i=0;i<MAX_CH_TOTAL-2;i++)
	{
		m_nlaVoltDiv[i] = 58;
	}
	laSetVoltDiv(m_nDeviceIndex,m_nlaVoltDiv);
}


void CHard::ReadData()
{
	int i=0;
	USHORT* pReadData[MAX_CH_NUM];
	USHORT* nData[MAX_CH_NUM];
	for(i=0;i<MAX_CH_NUM;i++)
	{
		pReadData[i] = new USHORT[m_stControl.nReadDataLen];
		nData[i] = new USHORT[m_stControl.nReadDataLen];
		memset(pReadData[i],0,m_stControl.nReadDataLen*sizeof(USHORT));
		memset(nData[i],0,m_stControl.nReadDataLen*sizeof(USHORT));
	}
	if(m_stControl.nTimeDIV > 9)
	{
		m_nReadOK = dsoHTGetData(m_nDeviceIndex,pReadData[0],pReadData[1],pReadData[2],pReadData[3],&m_stControl);
	}
	else 
	{
		m_nReadOK = dsoHTGetData(m_nDeviceIndex,nData[0],nData[1],nData[2],nData[3],&m_stControl);
		if(m_stControl.nTimeDIV > 7)
		{
			for(i=0;i<MAX_CH_NUM;i++)
			{
				if(((m_stControl.nCHSet >> i) & 0x01) == 1)//如果CH可用
				{
					{
						if(i<2)
						{
							dsoGetBufferDataByInsertData(nData[i],pReadData[i],i,&m_stControl,m_nInsertMode);
						}
						else
						{
							dsoGetlaBufferDataByInsertData(nData[i],pReadData[i],i,&m_stControl);
						}
					}
				}
			}
		}
		else
		{
			//BOOL bSingle = FALSE;
			USHORT* nDataBuffer;
			//ULONG nTriggerPoint = 0;
			ULONG nState[MAX_CH_TOTAL];
			nDataBuffer = new USHORT[(m_stControl.nReadDataLen-BUF_10K_LEN)+BUF_40K_LEN];
			if(m_stControl.nTriggerSource < MAX_CH_TOTAL)
			{
				int nSrc=0;
				if(m_stControl.nTriggerSource>3)
					nSrc=0;
				else
					nSrc=m_stControl.nTriggerSource;
				
				for(i=0;i<MAX_CH_NUM;i++) 
				{
					if(i<2)
					{
						dsoGetBufferDataByInsertData(nData[nSrc],nDataBuffer,nSrc,&m_stControl,m_nInsertMode);
						nState[i] = dsoSFFindTrigger(nDataBuffer,pReadData[i],&m_stControl);
						dsoGetSoftTriggerPos(m_stControl.nTimeDIV,i,nState);
						if(m_stControl.nTriggerSource == i)
						{
							continue;
						}
						if(((m_stControl.nCHSet >> i) & 0x01) == 1)//如果CH可用
						{
							dsoGetBufferDataByInsertData(nData[i],nDataBuffer,i,&m_stControl,m_nInsertMode);
							dsoSFFindTriggerCopy(nDataBuffer,pReadData[i],&m_stControl,nState[i]);
						}
					}
					else
					{
						dsoGetlaBufferDataByInsertData(nData[i],pReadData[i],i,&m_stControl);
					}
				}
				
			}
		}
	}
	if(m_nReadOK == 1)
	{
		for(i=0;i<MAX_CH_TOTAL;i++)
		{
			if(i<=2)
			{
				dsoGetDisplayDataFromSourceDataSingle(m_pSrcData[i], pReadData[i], m_nLeverPos, m_stControl.nReadDataLen, i);
			}
			else if(i<10)
			{
				dsoGetDisplayDataFromSourceDataSingle(m_pSrcData[i], pReadData[2], m_nLeverPos, m_stControl.nReadDataLen, i);
			}
			else if(i<18)
			{
				dsoGetDisplayDataFromSourceDataSingle(m_pSrcData[i], pReadData[3], m_nLeverPos, m_stControl.nReadDataLen, i);
			}
		}
	}

	for(i=0;i<MAX_CH_NUM;i++)
	{
		delete pReadData[i];
		delete nData[i];
	}
}
