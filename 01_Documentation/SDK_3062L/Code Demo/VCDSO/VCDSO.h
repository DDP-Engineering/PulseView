// VCDSO.h : main header file for the VCDSO application
//

#if !defined(AFX_VCDSO_H__831167DC_2BB2_44FF_8A06_4725EDBEA844__INCLUDED_)
#define AFX_VCDSO_H__831167DC_2BB2_44FF_8A06_4725EDBEA844__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#ifndef __AFXWIN_H__
	#error include 'stdafx.h' before including this file for PCH
#endif

#include "resource.h"       // main symbols

/////////////////////////////////////////////////////////////////////////////
// CVCDSOApp:
// See VCDSO.cpp for the implementation of this class
//

class CVCDSOApp : public CWinApp
{
public:
	CVCDSOApp();

// Overrides
	// ClassWizard generated virtual function overrides
	//{{AFX_VIRTUAL(CVCDSOApp)
	public:
	virtual BOOL InitInstance();
	//}}AFX_VIRTUAL

// Implementation
	//{{AFX_MSG(CVCDSOApp)
	afx_msg void OnAppAbout();
		// NOTE - the ClassWizard will add and remove member functions here.
		//    DO NOT EDIT what you see in these blocks of generated code !
	//}}AFX_MSG
	DECLARE_MESSAGE_MAP()
};


/////////////////////////////////////////////////////////////////////////////

//{{AFX_INSERT_LOCATION}}
// Microsoft Visual C++ will insert additional declarations immediately before the previous line.

#endif // !defined(AFX_VCDSO_H__831167DC_2BB2_44FF_8A06_4725EDBEA844__INCLUDED_)
