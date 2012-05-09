/*------------------------------------------------------------------------------
 *
 *  Copyright (C) 2003 Open Microscopy Environment
 *      Massachusetts Institute of Technology,
 *      National Institutes of Health,
 *      University of Dundee
 *
 *
 *
 *    This library is free software; you can redistribute it and/or
 *    modify it under the terms of the GNU Lesser General Public
 *    License as published by the Free Software Foundation; either
 *    version 2.1 of the License, or (at your option) any later version.
 *
 *    This library is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *    Lesser General Public License for more details.
 *
 *    You should have received a copy of the GNU Lesser General Public
 *    License along with this library; if not, write to the Free Software
 *    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 *------------------------------------------------------------------------------
 */




/*------------------------------------------------------------------------------
 *
 * Written by:	Chris Allan <callan@blackcat.ca>   01/2004
 * 
 *------------------------------------------------------------------------------
 */

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif  /* HAVE_CONFIG_H */

#include <stdio.h>
#include <string.h>
#include <assert.h>

#include "method.h"

unsigned int
get_method_by_name(char * m_name)
{
	/* Sanity check (FATAL) */
	assert(m_name != NULL);

	/* Pixels comparisions */
	if (strcmp(m_name, "Pixels") == 0) return M_PIXELS;
	if (strcmp(m_name, "NewPixels") == 0) return M_NEWPIXELS;
	if (strcmp(m_name, "PixelsInfo") == 0) return M_PIXELSINFO;
	if (strcmp(m_name, "PixelsSHA1") == 0) return M_PIXELSSHA1;
	if (strcmp(m_name, "SetPixels") == 0) return M_SETPIXELS;
	if (strcmp(m_name, "GetPixels") == 0) return M_GETPIXELS;
	if (strcmp(m_name, "FinishPixels") == 0) return M_FINISHPIXELS;
	if (strcmp(m_name, "Convert") == 0) return M_CONVERT;
	if (strcmp(m_name, "DeletePixels") == 0) return M_DELETEPIXELS;
	

	/* Row comparisions */
	if (strcmp(m_name, "SetRows") == 0) return M_SETROWS;
	if (strcmp(m_name, "GetRows") == 0) return M_GETROWS;
	if (strcmp(m_name, "ConvertRows") == 0) return M_CONVERTROWS;

	/* Plane comparisions */
	if (strcmp(m_name, "Plane") == 0) return M_PLANE;
	if (strcmp(m_name, "SetPlane") == 0) return M_SETPLANE;
	if (strcmp(m_name, "GetPlane") == 0) return M_GETPLANE;
	if (strcmp(m_name, "GetPlaneStats") == 0) return M_GETPLANESSTATS;
	if (strcmp(m_name, "GetPlaneHist") == 0) return M_GETPLANESHIST;
	if (strcmp(m_name, "ConvertPlane") == 0) return M_CONVERTPLANE;
	if (strcmp(m_name, "ConvertTIFF") == 0) return M_CONVERTTIFF;
	
	/* Stack comparisions */
	if (strcmp(m_name, "Stack") == 0) return M_STACK;
	if (strcmp(m_name, "SetStack") == 0) return M_SETSTACK;
	if (strcmp(m_name, "GetStack") == 0) return M_GETSTACK;
	if (strcmp(m_name, "GetStackStats") == 0) return M_GETSTACKSTATS;
	if (strcmp(m_name, "GetStackHist") == 0) return M_GETSTACKHIST;
	if (strcmp(m_name, "ConvertStack") == 0) return M_CONVERTSTACK;

	/* ROI comparisions */
	if (strcmp(m_name, "SetROI") == 0) return M_SETROI;
	if (strcmp(m_name, "GetROI") == 0) return M_GETROI;

	/* File comparisions */
	if (strcmp(m_name, "FileSHA1") == 0) return M_FILESHA1;
	if (strcmp(m_name, "FileInfo") == 0) return M_FILEINFO;
	if (strcmp(m_name, "ReadFile") == 0) return M_READFILE;
	if (strcmp(m_name, "UploadFile") == 0) return M_UPLOADFILE;
	if (strcmp(m_name, "DeleteFile") == 0) return M_DELETEFILE;
	if (strcmp(m_name, "ZipFiles") == 0) return M_ZIPFILES;

	/* Utility/other comparisons */
	if (strcmp(m_name, "GetLocalPath") == 0) return M_GETLOCALPATH;
	if (strcmp(m_name, "ImportOMEfile") == 0) return M_IMPORTOMEFILE;
	if (strcmp(m_name, "ExportOMEfile") == 0) return M_EXPORTOMEFILE;
	if (strcmp(m_name, "Composite") == 0) return M_COMPOSITE;
	if (strcmp(m_name, "GetThumb") == 0) return M_GETTHUMB;
	if (strcmp(m_name, "IsOMExml") == 0) return M_ISOMEXML;

	/* fprintf(stderr, "Unknown method '%s'.\n", m_name); */
	return 0;  /* Unknown method */
}

