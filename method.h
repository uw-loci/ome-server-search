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

/* METHOD RETRIEVAL FUNCTIONS */

unsigned int
get_method_by_name(char * m_name);

/* SUPPORTED CGI METHODS */

	/* PIXELS METHODS */
#define M_PIXELS        1
#define M_NEWPIXELS     2
#define M_PIXELSINFO    3
#define M_PIXELSSHA1    4
#define M_SETPIXELS     5
#define M_GETPIXELS     6
#define M_FINISHPIXELS  7
#define M_CONVERT       8
#define M_DELETEPIXELS  9

	/* ROW METHODS */
#define M_SETROWS       10
#define M_GETROWS       11
#define M_CONVERTROWS   12

	/* PLANE METHODS */
#define M_PLANE         20
#define M_SETPLANE      21
#define M_GETPLANE      22
#define M_GETPLANESSTATS 23
#define M_CONVERTPLANE  24
#define M_CONVERTTIFF   25
#define M_GETPLANESHIST 26  

	/* STACK METHODS */
#define M_STACK         30
#define M_SETSTACK      31
#define M_GETSTACK      32
#define M_GETSTACKSTATS 33
#define M_CONVERTSTACK  34
#define M_GETSTACKHIST  35 

	/* ROI METHODS */
#define M_SETROI        40
#define M_GETROI        41

	/* FILE METHODS */
#define M_FILEINFO      50
#define M_FILESHA1      51 
#define M_UPLOADFILE    52
#define M_READFILE      53
#define M_DELETEFILE    54
#define M_ZIPFILES      55

	/* OTHER/UTILITY METHODS */
#define M_GETLOCALPATH  60
#define M_IMPORTOMEFILE 61
#define M_EXPORTOMEFILE 62
#define M_COMPOSITE     63
#define M_GETTHUMB      64
#define M_ISOMEXML      65

