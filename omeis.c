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
 * Written by:	Ilya G. Goldberg <igg@nih.gov>   11/2003
 *
 *------------------------------------------------------------------------------
 */

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif  /* HAVE_CONFIG_H */

#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/param.h>
#include <dirent.h>

#include "Pixels.h"
#include "File.h"
#include "OMEIS_Error.h"
#include "omeis.h"
#include "cgi.h"
#include "method.h"
#include "composite.h"
#include "xmlBinaryResolution.h"
#include "xmlBinaryInsertion.h"
#include "xmlIsOME.h"
#include "archive.h"

#ifndef OMEIS_ROOT
#define OMEIS_ROOT "."
#endif


static
int
dispatch (char **param)
{
	PixelsRep *thePixels;
	FileRep *theFile;
	pixHeader *head;
	size_t nPix=0, nIO=0;
	char *theParam,rorw='r',iam_BigEndian=1;
	OID ID=0,resultID;
	size_t offset=0, file_offset=0;
	unsigned long long scan_off, scan_length, scan_ID;
	unsigned char isLocalFile=0;
	char *dims;
	int isSigned,isFloat;
	int numInts,numX,numY,numZ,numC,numT,numB;
	int force,result;
	int fd;
	unsigned long z,dz,c,dc,t,dt;
	planeInfo *planeInfoP;
	stackInfo *stackInfoP;
	unsigned long uploadSize;
	unsigned long length;
	OID fileID;
	struct stat fStat;
	FILE *file;
	char file_path[MAXPATHLEN],file_path2[MAXPATHLEN];
	unsigned long tiffDir=0;
	int i;

	/* Co-ordinates */
	ome_coord theC = -1, theT = -1, theZ = -1, theY = -1;

	/* Dimensions */
	ome_dim sizeX = -1, sizeY = -1;

#ifdef DEBUG
	char **cgivars=param;
	while (*cgivars) {
		fprintf (stderr,"%s", *cgivars);
		cgivars++;
		fprintf (stderr,"=%s ", *cgivars);
		cgivars++;
	}
#endif

	/* XXX: char * method should be able to disappear at some point */
	char *method;
	unsigned int m_val;


	if (! (method = get_param (param,"Method")) ) {
		OMEIS_ReportError ("OMEIS", NULL, ID, "Method parameter missing");
		return (-1);
	}

	m_val = get_method_by_name(method);
	/* Trap for inputed method name strings that don't correspond to implemented methods */
	if (m_val == 0){
			OMEIS_ReportError (method, NULL, ID, "Method doesn't exist");
			return (-1);
	}

	/* END (method operations) */

	/* ID requirements */
	if ( (theParam = get_param (param,"PixelsID")) ) {
		sscanf (theParam,"%llu",&scan_ID);
		ID = (OID) scan_ID;
		if (ID <= 0) {
			OMEIS_ReportError (method, NULL, ID, "PixelsID must be positive.");
			return (-1);
		}
	} else if (m_val != M_NEWPIXELS   &&
			 m_val != M_FILEINFO      &&
			 m_val != M_FILESHA1      &&
			 m_val != M_READFILE      &&
			 m_val != M_UPLOADFILE    &&
			 m_val != M_IMPORTOMEFILE &&
			 m_val != M_EXPORTOMEFILE &&
			 m_val != M_ISOMEXML      &&
			 m_val != M_DELETEFILE    &&
			 m_val != M_GETLOCALPATH  &&
		         m_val != M_ZIPFILES) {
			OMEIS_ReportError (method, NULL, ID, "PixelsID Parameter missing");
			return (-1);
	}

	if ((theParam = get_lc_param(param,"IsLocalFile"))) {
		if ( !strcmp (theParam,"true") || !strcmp (theParam,"1") ) isLocalFile = 1;
	} else
		isLocalFile = 0;


	if ( (theParam = get_param (param,"theZ")) )
		sscanf (theParam,"%d",&theZ);

	if ( (theParam = get_param (param,"theC")) )
		sscanf (theParam,"%d",&theC);

	if ( (theParam = get_param (param,"theT")) )
		sscanf (theParam,"%d",&theT);

	if ( (theParam = get_param (param,"theY")) )
		sscanf (theParam,"%d",&theY);

	if ( (theParam = get_lc_param (param,"BigEndian")) ) {
		if (!strcmp (theParam,"0") || !strcmp (theParam,"false") ) iam_BigEndian=0;
	}

	/* ---------------------- */
	/* SIMPLE METHOD DISPATCH */
	switch (m_val) {
		case M_NEWPIXELS:
			isSigned = 0;
			isFloat = 0;

			if (! (dims = get_param (param,"Dims")) ) {
				OMEIS_ReportError (method, NULL, ID, "Dims Parameter missing");
				return (-1);
			}
			numInts = sscanf (dims,"%d,%d,%d,%d,%d,%d",&numX,&numY,&numZ,&numC,&numT,&numB);
			if (numInts < 6 || numX < 1 || numY < 1 || numZ < 1 || numC < 1 || numT < 1 || numB < 1) {
				OMEIS_ReportError (method, NULL, ID,
					"Dims improperly formed.  Expecting numX,numY,numZ,numC,numT,numB.  All positive integers.");
				return (-1);
			}

			if ( (theParam = get_lc_param (param,"IsFloat")) ) {
				if (!strcmp (theParam,"1") || !strcmp (theParam,"true") ) {
					isFloat  = 1;
					isSigned = 1;
				}
			}

			if ( (theParam = get_lc_param (param,"IsSigned")) ) {
				if (!strcmp (theParam,"1") || !strcmp (theParam,"true") ) isSigned=1;

				/* [Bug 536] isFloat=1 and isSigned=0 is not allowed */
				if ( (!strcmp (theParam,"0") || !strcmp (theParam,"false")) && isFloat) {
					OMEIS_ReportError (method, NULL, ID,"IsSigned must be 1 for floating-point pixels, not %s", theParam);
					return (-1);
				}
			}

			if ( !(numB == 1 || numB == 2 || numB == 4) ) {
				OMEIS_ReportError (method, NULL, ID,"Bytes per pixel must be 1, 2 or 4, not %d", numB);
				return (-1);
			}

			if ( numB != 4 && isFloat ) {
				OMEIS_ReportError (method, NULL, ID,"Bytes per pixel must be 4 for floating-point pixels, not %d", numB);
				return (-1);
			}

			if (! (thePixels = NewPixels (numX,numY,numZ,numC,numT,numB,isSigned,isFloat)) ) {
				OMEIS_ReportError (method, NULL, ID, "NewPixels failed.");
				return (-1);
			}

			HTTP_ResultType ("text/plain");
			fprintf (stdout,"%llu\n",(unsigned long long)thePixels->ID);
			freePixelsRep (thePixels);

			break;
		case M_PIXELSINFO:
        	if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'i',1)) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			head = thePixels->head;

			HTTP_ResultType ("text/plain");
			fprintf(stdout,"Dims=%d,%d,%d,%d,%d,%hhu\n",
					head->dx,head->dy,head->dz,head->dc,head->dt,head->bp);
			fprintf(stdout,"Finished=%hhu\nSigned=%hhu\nFloat=%hhu\n",
					head->isFinished,head->isSigned,head->isFloat);

			fprintf(stdout,"SHA1=");
			print_md(head->sha1);
			fprintf(stdout,"\n");

			freePixelsRep (thePixels);

			break;
		case M_PIXELSSHA1:
        	if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'i',1)) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			head = thePixels->head;

			HTTP_ResultType ("text/plain");
			print_md(head->sha1);
			fprintf(stdout,"\n");

			freePixelsRep (thePixels);

			break;
		case M_FINISHPIXELS:
			force = 0;
			result = 0;

			if (!ID) return (-1);
			if ( (theParam = get_param (param,"Force")) )
				sscanf (theParam,"%d",&force);

			if (! (thePixels = GetPixelsRep (ID,'w',iam_BigEndian)) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			resultID = FinishPixels (thePixels,force);

			if ( resultID == 0) {
				OMEIS_ReportError (method, "PixelsID", ID, "FinishPixels failed.");
				freePixelsRep (thePixels);
				return (-1);
			} else {
				HTTP_ResultType ("text/plain");
				fprintf (stdout,"%llu\n",(unsigned long long)resultID);
			}

			freePixelsRep (thePixels);
			break;
		case M_DELETEPIXELS:
			if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'i',iam_BigEndian)) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			if (!ExpungePixels (thePixels)) {
				OMEIS_ReportError (method, "PixelsID", ID, "ExpungePixels failed.");
				return (-1);
			}

			HTTP_ResultType ("text/plain");
			fprintf (stdout,"%llu\n",(unsigned long long)thePixels->ID);
			freePixelsRep (thePixels);

			break;
		case M_GETPLANESSTATS:
			if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'r',bigEndian())) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			if (! (planeInfoP = thePixels->planeInfos) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "planeInfos are NULL");
				freePixelsRep (thePixels);
				return (-1);
			}

			head = thePixels->head;

			dz = head->dz;
			dc = head->dc;
			dt = head->dt;
			HTTP_ResultType ("text/plain");

			for (t = 0; t < dt; t++)
				for (c = 0; c < dc; c++)
					for (z = 0; z < dz; z++) {
						fprintf (stdout,"%lu\t%lu\t%lu\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\n",
							 c,t,z,planeInfoP->min,planeInfoP->max,planeInfoP->mean,planeInfoP->sigma,planeInfoP->geomean,planeInfoP->geosigma,
							 planeInfoP->centroid_x, planeInfoP->centroid_y,
							 planeInfoP->sum_i, planeInfoP->sum_i2, planeInfoP->sum_log_i,
							 planeInfoP->sum_xi, planeInfoP->sum_yi, planeInfoP->sum_zi
						);

						planeInfoP++;
					}

			freePixelsRep (thePixels);

			break;
		case M_GETPLANESHIST:
			if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'r',bigEndian())) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			if (! (planeInfoP = thePixels->planeInfos) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "planeInfos are NULL");
				freePixelsRep (thePixels);
				return (-1);
			}

			head = thePixels->head;

			dz = head->dz;
			dc = head->dc;
			dt = head->dt;
			HTTP_ResultType ("text/plain");
			for (t = 0; t < dt; t++)
				for (c = 0; c < dc; c++)
					for (z = 0; z < dz; z++) {
						fprintf(stdout,"%lu\t%lu\t%lu\t", c,t,z);
						for (i = 0; i < NUM_BINS; i++)
							fprintf(stdout,"%lu\t", planeInfoP->hist[i]);
						fprintf(stdout,"\n");
						planeInfoP++;
					}

			freePixelsRep (thePixels);
			break;
		case M_GETSTACKSTATS:
			if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'r',bigEndian())) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			if (! (stackInfoP = thePixels->stackInfos) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "stackInfos are NULL");
				freePixelsRep (thePixels);
				return (-1);
			}

			head = thePixels->head;

			dz = head->dz;
			dc = head->dc;
			dt = head->dt;
			HTTP_ResultType ("text/plain");

			for (t = 0; t < dt; t++)
				for (c = 0; c < dc; c++) {
					fprintf (stdout,"%lu\t%lu\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\n",
						 c,t,stackInfoP->min,stackInfoP->max,stackInfoP->mean,stackInfoP->sigma,stackInfoP->geomean,stackInfoP->geosigma,
						 stackInfoP->centroid_x, stackInfoP->centroid_y, stackInfoP->centroid_z,
						 stackInfoP->sum_i, stackInfoP->sum_i2, stackInfoP->sum_log_i,
						 stackInfoP->sum_xi, stackInfoP->sum_yi, stackInfoP->sum_zi
					);
					stackInfoP++;
				}

			freePixelsRep (thePixels);

			break;
		case M_GETSTACKHIST:
		if (!ID) return (-1);

			if (! (thePixels = GetPixelsRep (ID,'r',bigEndian())) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			if (! (stackInfoP = thePixels->stackInfos) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "stackInfos are NULL");
				freePixelsRep (thePixels);
				return (-1);
			}

			head = thePixels->head;

			dz = head->dz;
			dc = head->dc;
			dt = head->dt;
			HTTP_ResultType ("text/plain");

			for (t = 0; t < dt; t++)
				for (c = 0; c < dc; c++) {
					fprintf(stdout,"%lu\t%lu\t", c,t);
					for (i = 0; i < NUM_BINS; i++)
						fprintf(stdout,"%lu\t", stackInfoP->hist[i]);
					fprintf(stdout,"\n");
					stackInfoP++;
				}

			freePixelsRep (thePixels);

			break;
		case M_UPLOADFILE:
			uploadSize = 0;
			if ( (theParam = get_param (param,"UploadSize")) ) {
				sscanf (theParam,"%llu",&scan_length);
				uploadSize = (unsigned long)scan_length;
			} else {
				OMEIS_ReportError (method, NULL, ID,"UploadSize must be specified!");
				return (-1);
			}
			if ( (ID = UploadFile (get_param (param,"File"),uploadSize,isLocalFile) ) == 0) {
				OMEIS_ReportError (method, NULL, ID, "UploadFile failed.");
				return (-1);
			} else {
				HTTP_ResultType ("text/plain");
				fprintf (stdout,"%llu\n",(unsigned long long)ID);
			}

			break;
		case M_GETLOCALPATH:
			fileID = 0;

			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			}

			if (ID) {
				if (! (thePixels = GetPixelsRep (ID,'i',bigEndian())) ) {
					OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
					return (-1);
				}
				strcpy (file_path,thePixels->path_rep);
				freePixelsRep (thePixels);
			} else if (fileID) {
				strcpy (file_path,"Files/");
				if (! getRepPath (fileID,file_path,0)) {
					OMEIS_ReportError (method, "FileID", fileID, "getRepPath failed");
					return (-1);
				}
			} else strcpy (file_path,"");

			HTTP_ResultType ("text/plain");
			fprintf (stdout,"%s\n",file_path);

			break;
		case M_DELETEFILE:
			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, NULL, fileID,"FileID must be specified!");
				return (-1);
			}

			if ( !(theFile = GetFileRep (fileID,0,0)) ) {
				OMEIS_ReportError (method, "FileID", fileID, "GetFileRep failed.");
				return (-1);
			}

			if ( !ExpungeFile (theFile)) {
				OMEIS_ReportError (method, "FileID", fileID, "ExpungeFile failed.");
				return (-1);
			}

			HTTP_ResultType ("text/plain");
			fprintf (stdout,"%llu\n",(unsigned long long)theFile->ID);
			freeFileRep (theFile);

			break;
		case M_FILEINFO:
			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, NULL, ID,"FileID must be specified!");
				return (-1);
			}

			if ( !(theFile = newFileRep (fileID)) ) {
				OMEIS_ReportError (method, "FileID", fileID, "Could not make new repository file");
				return (-1);
			}

			if (GetFileInfo (theFile) < 0) {
				freeFileRep (theFile);
				OMEIS_ReportError (method, "FileID", fileID,"Could not get file info");
				return (-1);
			}

			if (GetFileAliases (theFile) < 0) {
				freeFileRep (theFile);
				OMEIS_ReportError (method, "FileID", fileID,"Could not get aliases");
				return (-1);
			}

			HTTP_ResultType ("text/plain");
			fprintf (stdout,"Name=%s\nLength=%lu\nSHA1=",theFile->file_info.name,(unsigned long)theFile->size_rep);

			/* Print our lovely and useful SHA1. */
			print_md(theFile->file_info.sha1);  /* Convenience provided by digest.c */
			printf("\n");

			/* Indicate the original if we're an alias */
			if (theFile->file_info.isAlias) {
				fprintf (stdout,"IsAlias=%llu\n",theFile->file_info.isAlias);
			}

			/* Print out any aliases */
			if (theFile->file_info.nAliases) {
				fprintf (stdout,"HasAliases=");
				for (i=0; i<theFile->file_info.nAliases; i++) {
					fprintf (stdout,"%llu",(unsigned long long) (theFile->aliases[i].ID) );
					if (i < theFile->file_info.nAliases-1) fprintf (stdout,"\t");
				}
				fprintf (stdout,"\n");
			}
			freeFileRep (theFile);

			break;
		case M_FILESHA1:
			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, NULL, fileID,"FileID must be specified!");
				return (-1);
			}

			if ( !(theFile = newFileRep (fileID)) ) {
				OMEIS_ReportError (method, "FileID", fileID,"newFileRep failed");
				return (-1);
			}

			if (GetFileInfo (theFile) < 0) {
				freeFileRep (theFile);
				OMEIS_ReportError (method, "FileID", fileID,"Could not get info for repository file");
				return (-1);
			}


			HTTP_ResultType ("text/plain");

			/* Print our lovely and useful SHA1. */
			print_md(theFile->file_info.sha1);  /* Convenience provided by digest.c */
			printf("\n");
			freeFileRep (theFile);

			break;
		case M_READFILE:
			offset = 0;
			length = 0;

			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, NULL, ID,"FileID must be specified!");
				return (-1);
			}

			if ( !(theFile = GetFileRep (fileID,offset,length)) ) {
				OMEIS_ReportError (method, "FileID", fileID, "GetFileRep failed.");
				return (-1);
			}

			if (stat (theFile->path_rep, &fStat) < 0) {
				OMEIS_ReportError (method, "FileID", fileID,"Could not get size of file");
				freeFileRep (theFile);
				return (-1);
			}
			theFile->size_rep = fStat.st_size;

			if ( (theParam = get_param (param,"Offset")) ) {
				sscanf (theParam,"%llu",&scan_off);
				offset = (size_t)scan_off;
			}

			if ( (theParam = get_param (param,"Length")) ) {
				sscanf (theParam,"%llu",&scan_length);
				length = (size_t)scan_length;
			} else {
				length = (size_t)theFile->size_rep - offset;
			}

			/* check if the offset is past EOF */
			if (offset >= theFile->size_rep) {
				OMEIS_ReportError (method, "FileID", fileID, "Offset is greater than file's length.");
				return (-1);
			}

			/* Check that reading the specified number of bytes will not send us past EOF.
			   If so, resize the length so we read as much as possible but no more */
			if (offset+length >= theFile->size_rep)
				length = theFile->size_rep - offset;

			if (offset == 0 && length == theFile->size_rep && getenv("REQUEST_METHOD") ) {
				if (GetFileInfo (theFile) < 0) {
					OMEIS_ReportError (method, "FileID", fileID, "GetFileInfo failed.");
					freeFileRep (theFile);
					return (-1);
				}
				fprintf (stdout,"Content-Disposition: attachment; filename=\"%s\"\r\n",theFile->file_info.name);
			}

			HTTP_ResultType ("application/octet-stream");
			fwrite ((u_int8_t *) theFile->file_buf + offset,length,1,stdout);
			freeFileRep (theFile);

			break;
		case M_ZIPFILES:
		  if (zipFiles(param))
		    return (-1);
		  break;
		
		case M_IMPORTOMEFILE:
			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, NULL, ID,"FileID must be specified!");
				return (-1);
			}

			strcpy (file_path,"Files/");
			if (! getRepPath (fileID,file_path,0)) {
				OMEIS_ReportError (method, "FileID", fileID, "getRepPath failed.");
				return (-1);
			}

			/*
			  libxml2 can directly read gzip files, but not bzip2.
			  Inflate if bzip2, otherwise parse .gz directly.
			*/
			if ( stat (file_path,&fStat) != 0 ) {
				strcpy (file_path2,file_path);
				strcat (file_path2,".gz");
				if ( stat (file_path2,&fStat) != 0 ) {
					if ( (fd = openRepFile (file_path, O_RDONLY)) < 0) {
						OMEIS_ReportError (method, "FileID", fileID, "openRepFile failed.");
						return (-1);
					}
					close (fd);
				} else {
					strcpy (file_path,file_path2);
				}
			}
			HTTP_ResultType ("text/xml");
			parse_xml_file( file_path );

			break;
		case M_EXPORTOMEFILE:
			uploadSize = 0;
			if ( (theParam = get_param (param,"UploadSize")) ) {
				sscanf (theParam,"%llu",&scan_length);
				uploadSize = (unsigned long)scan_length;
			} else {
				OMEIS_ReportError (method, NULL, ID,"UploadSize must be specified!");
				return (-1);
			}
			if ( (ID = UploadFile (get_param (param,"File"),uploadSize,isLocalFile) ) == 0) {
				OMEIS_ReportError (method, NULL, (OID)0, "UploadFile failed.");
				return (-1);
			}

			HTTP_ResultType ("text/plain");
			strcpy (file_path,"Files/");
			if (! getRepPath (ID,file_path,0)) {
				OMEIS_ReportError (method, "FileID", ID, "getRepPath failed.");
				return (-1);
			}

			xmlInsertBinaryData( file_path, iam_BigEndian );
			/* This is supposed to parse from STDIN. It works when input
			is piped in and omeis is ran as a command line program. It
			reports 'Empty Document' when input is posted on a form and
			omeis is ran as a cgi.
			xmlInsertBinaryData( "-", iam_BigEndian );*/

			if ( !(theFile = GetFileRep (ID,0,0)) ) {
				OMEIS_ReportError (method, "FileID", ID, "GetFileRep failed.");
				return (-1);
			}
			if ( !ExpungeFile (theFile)) {
				OMEIS_ReportError (method, "FileID", fileID, "ExpungeFile failed.");
				return (-1);
			}

			freeFileRep (theFile);

			break;

		case M_ISOMEXML:
			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, NULL, ID,"FileID must be specified!");
				return (-1);
			}

			strcpy (file_path,"Files/");
			if (! getRepPath (fileID,file_path,0)) {
				OMEIS_ReportError (method, "FileID", fileID, "getRepPath failed.");
				return (-1);
			}

			if ( stat (file_path,&fStat) != 0 ) {
				strcpy (file_path2,file_path);
				strcat (file_path2,".gz");
				if ( stat (file_path2,&fStat) != 0 ) {
					if ( (fd = openRepFile (file_path, O_RDONLY)) < 0) {
						OMEIS_ReportError (method, "FileID", fileID, "openRepFile failed.");
						return (-1);
					}
					close (fd);
				} else {
					strcpy (file_path,file_path2);
				}
			}
			HTTP_ResultType ("text/plain");
			result = check_xml_file( file_path );
			fprintf (stdout,"%d\n",result);

			break;
		case M_CONVERT:
		case M_CONVERTSTACK:
		case M_CONVERTPLANE:
		case M_CONVERTTIFF:
		case M_CONVERTROWS:
			if ( (theParam = get_param (param,"FileID")) ) {
				sscanf (theParam,"%llu",&scan_ID);
				fileID = (OID)scan_ID;
			} else {
				OMEIS_ReportError (method, "PixelsID", ID,"FileID must be specified!");
				return (-1);
			}

			if ( (theParam = get_param (param,"Offset")) ) {
				sscanf (theParam,"%llu",&scan_off);
				file_offset = (size_t)scan_off;
			}

			tiffDir=0;
			if ( (theParam = get_param (param,"TIFFDirIndex")) ) {
				sscanf (theParam,"%lu",&tiffDir);
			}

			if (! (thePixels = GetPixelsRep (ID,'w',iam_BigEndian)) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}
			head = thePixels->head;
			nPix = head->dx*head->dy*head->dz*head->dc*head->dt;
			offset = 0;

			if (m_val == M_CONVERTSTACK) {
				if (theC < 0 || theT < 0) {
					OMEIS_ReportError (method, "PixelsID", ID,"Parameters theC and theT must be specified to do operations on stacks." );
					freePixelsRep (thePixels);
					return (-1);
				}
				nPix = head->dx*head->dy*head->dz;
				if (!CheckCoords (thePixels, 0, 0, 0, theC, theT)){
					OMEIS_ReportError (method, "PixelsID", ID,"Parameters theC, theT (%d,%d) must be in range (%d,%d).",theC,theT,head->dc-1,head->dt-1);
					freePixelsRep (thePixels);
					return (-1);
				}
				offset = GetOffset (thePixels, 0, 0, 0, theC, theT);
			} else if (m_val == M_CONVERTPLANE || m_val == M_CONVERTTIFF) {
				if (theZ < 0 || theC < 0 || theT < 0) {
					OMEIS_ReportError (method, "PixelsID", ID,"Parameters theZ, theC and theT must be specified to do operations on planes." );
					freePixelsRep (thePixels);
					return (-1);
				}

				nPix = head->dx*head->dy;
				if (!CheckCoords (thePixels, 0, 0, theZ, theC, theT)){
					OMEIS_ReportError (method, "PixelsID", ID,"Parameters theZ, theC, theT (%d,%d,%d) must be in range (%d,%d,%d).",theZ,theC,theT,head->dz-1,head->dc-1,head->dt-1);
					freePixelsRep (thePixels);
					return (-1);
				}

				offset = GetOffset (thePixels, 0, 0, theZ, theC, theT);

			} else if (m_val == M_CONVERTROWS) {
				long nRows=1;

				if ( (theParam = get_param (param,"nRows")) )
					sscanf (theParam,"%ld",&nRows);
				if (theY < 0 ||theZ < 0 || theC < 0 || theT < 0) {
					OMEIS_ReportError (method, "PixelsID", ID,"Parameters theY, theZ, theC and theT must be specified to do operations on rows." );
					freePixelsRep (thePixels);
					return (-1);
				}

				nPix = nRows*head->dy;
				if (!CheckCoords (thePixels, 0, theY, theZ, theC, theT)){
					OMEIS_ReportError (method, "PixelsID", ID,"Parameters theY, theZ, theC, theT (%d,%d,%d,%d) must be in range (%d,%d,%d,%d).",
						theY,theZ,theC,theT,head->dy-1,head->dz-1,head->dc-1,head->dt-1);
					freePixelsRep (thePixels);
					return (-1);
				}
				if (theY+nRows-1 >= head->dy) {
					OMEIS_ReportError (method, "PixelsID", ID,"theY + nRows (%d + %ld = %ld) must be less than dY (%d).",
						theY,nRows,theY+nRows,head->dy);
					freePixelsRep (thePixels);
					return (-1);
				}
				offset = GetOffset (thePixels, 0, theY, theZ, theC, theT);
			}

			if ( !(theFile = GetFileRep (fileID,0,0)) ) {
				OMEIS_ReportError (method, "FileID", fileID, "GetFileRep failed.");
				return (-1);
			}

			if (m_val == M_CONVERTTIFF)
				nIO = ConvertTIFF (thePixels, theFile, theZ, theC, theT, tiffDir, 1);
			else
				nIO = ConvertFile (thePixels, theFile, file_offset, offset, nPix, 1);
			if (nIO != nPix) {
				OMEIS_ReportError (method, "PixelsID", ID,
					"Did not convert correct number of pixels.  Expected %llu, got %llu",
					(unsigned long long)nPix, (unsigned long long)nIO);
				freePixelsRep (thePixels);
				freeFileRep   (theFile);
				return (-1);
			} else {

				/* compute the Pixel's statistics as appropriate */
				switch (m_val) {
					case M_CONVERT:
						FinishStats (thePixels, 0);
						break;
					case M_CONVERTSTACK:
						DoStackStats (thePixels, theC, theT);
						break;
					case M_CONVERTPLANE:
					case M_CONVERTTIFF:
						DoPlaneStats (thePixels, theZ, theC, theT);
						break;
				}
				freePixelsRep (thePixels);
				freeFileRep   (theFile);
				HTTP_ResultType ("text/plain");
				fprintf (stdout,"%ld\n", (long) nIO);
			}

			break;

		case M_COMPOSITE:
			if (theZ < 0 || theT < 0) {
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theZ, and theT must be specified for the composite method." );
				return (-1);
			}
			if (! (thePixels = GetPixelsRep (ID,'r',bigEndian())) ) {
				OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
				return (-1);
			}

			if (DoComposite (thePixels, theZ, theT, param) < 0) {
				OMEIS_ReportError (method, "PixelsID", ID, "Could not generate composite.");
				freePixelsRep (thePixels);
				return (-1);
			}
			freePixelsRep (thePixels);
			break;

		case M_GETTHUMB:
			if ( (theParam = get_param (param,"Size")) ) {
				sscanf (theParam,"%d,%d",&sizeX,&sizeY);
				if (sizeX <= 0 || sizeY <= 0) {
					OMEIS_ReportError (method, "PixelsID", ID,"Thumbnail size cannot be zero or negative.");
					return (-1);
				}
			}

			strcpy (file_path,"Pixels/");
			if (! getRepPath (ID,file_path,0)) {
				OMEIS_ReportError (method, "PixelsID", ID, "Could not get repository path");
				return (-1);
			}
			strcat (file_path,".thumb");

			if ( stat (file_path,&fStat) != 0 ) {
				OMEIS_ReportError (method, "PixelsID", ID,"Could not get information for thumbnail at %s",file_path);
				return (-1);
			}

			if ( !(file=fopen(file_path, "r")) ) {
				OMEIS_ReportError (method, "PixelsID", ID,"Could not open thumbnail at %s",file_path);
				return (-1);
			}

			if ( DoThumb(ID,file,sizeX,sizeY) < 0 ) {
				OMEIS_ReportError (method, "PixelsID", ID,"Could not get thumbnail at %s",file_path);
				fclose(file);
				return (-1);
			}
			fclose(file);


			break;
	} /* END case (method) */

	/* ----------------------- */
	/* COMPLEX METHOD DISPATCH */
	if (m_val == M_SETPIXELS || m_val == M_GETPIXELS ||
		m_val == M_SETROWS   || m_val == M_GETROWS  ||
		m_val == M_SETPLANE  || m_val == M_GETPLANE  ||
		m_val == M_SETSTACK  || m_val == M_GETSTACK) {
		char *filename = NULL;
		if (!ID) return (-1);


		if (strstr (method,"Set")) {
			rorw = 'w';
			if (!(filename = get_param(param,"Pixels"))) {
				OMEIS_ReportError(method, "PixelsID", ID,"No pixels specified");
			}
		} else rorw = 'r';

		if (! (thePixels = GetPixelsRep (ID,rorw,iam_BigEndian)) ) {
			OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
			return (-1);
		}

		head = thePixels->head;
		if (strstr (method,"Pixels")) {
			nPix = head->dx*head->dy*head->dz*head->dc*head->dt;
			offset = 0;
		} else if (strstr (method,"Stack")) {
			if (theC < 0 || theT < 0) {
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theC and theT must be specified to do operations on stacks." );
				freePixelsRep (thePixels);
				return (-1);
			}
			nPix = head->dx*head->dy*head->dz;
			if (!CheckCoords (thePixels, 0, 0, 0, theC, theT)){
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theC, theT (%d,%d) must be in range (%d,%d).",theC,theT,head->dc-1,head->dt-1);
				freePixelsRep (thePixels);
				return (-1);
			}
			offset = GetOffset (thePixels, 0, 0, 0, theC, theT);
		} else if (strstr (method,"Plane")) {
			if (theZ < 0 || theC < 0 || theT < 0) {
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theZ, theC and theT must be specified to do operations on planes." );
				freePixelsRep (thePixels);
				return (-1);
			}
			nPix = head->dx*head->dy;
			if (!CheckCoords (thePixels, 0, 0, theZ, theC, theT)){
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theZ, theC, theT (%d,%d,%d) must be in range (%d,%d,%d).",theZ,theC,theT,head->dz-1,head->dc-1,head->dt-1);
				freePixelsRep (thePixels);
				return (-1);
			}
			offset = GetOffset (thePixels, 0, 0, theZ, theC, theT);
		} else if (strstr (method,"Rows")) {
			long nRows=1;
			if ( (theParam = get_param (param,"nRows")) )
				sscanf (theParam,"%ld",&nRows);
			if (theY < 0 || theZ < 0 || theC < 0 || theT < 0) {
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theY, theZ, theC and theT must be specified to do operations on rows." );
				freePixelsRep (thePixels);
				return (-1);
			}
			if (!CheckCoords (thePixels, 0, theY, theZ, theC, theT)){
				OMEIS_ReportError (method, "PixelsID", ID,"Parameters theY, theZ, theC, theT (%d,%d,%d,%d) must be in range (%d,%d,%d,%d).",
					theY,theZ,theC,theT,head->dy-1,head->dz-1,head->dc-1,head->dt-1);
				freePixelsRep (thePixels);
				return (-1);
			}
			if (!CheckCoords (thePixels, 0, theY+nRows-1, theZ, theC, theT)){
				OMEIS_ReportError (method, "PixelsID", ID,"Number of rows (%d) and theY (%d) exceed maximum Y (%d).",
					nRows,theY,head->dy-1);
				freePixelsRep (thePixels);
				return (-1);
			}

			nPix = head->dx*nRows;
			offset = GetOffset (thePixels, 0, theY, theZ, theC, theT);
		}

		if (rorw == 'w')
			thePixels->IO_stream = openInputFile(filename,isLocalFile);
		else {
			thePixels->IO_stream = stdout;
			HTTP_ResultType ("application/octet-stream");
		}

		/*
		  Since we're going to stream to/from stdout/stdin at this point,
		  we can't report an error in a sensible way, so don't bother checking.
		  Its up to the client to figure out if the right number of pixels were read/written.
		*/
		nIO = DoPixelIO (thePixels, offset, nPix, rorw);
		if (rorw == 'w') {
			closeInputFile(thePixels->IO_stream,isLocalFile);
			HTTP_ResultType ("text/plain");
			fprintf (stdout,"%ld\n", (long) nIO);
		}

		freePixelsRep (thePixels);
	}

	else if (m_val == M_SETROI || m_val == M_GETROI) {
		char *ROI;
		int x0,y0,z0,c0,t0,x1,y1,z1,c1,t1;
		char *filename=NULL;

		if (!ID) return (-1);
		if (m_val == M_SETROI) {
			rorw = 'w';
			if (!(filename = get_param(param,"Pixels"))) {
				OMEIS_ReportError(method, "PixelsID", ID,"No pixels specified");
			}
		} else rorw = 'r';

		if ( !(ROI = get_param (param,"ROI")) ) {
			OMEIS_ReportError (method, "PixelsID", ID,"ROI Parameter required for the %s method",method);
			return (-1);
		}

		numInts = sscanf (ROI,"%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",&x0,&y0,&z0,&c0,&t0,&x1,&y1,&z1,&c1,&t1);
		if (numInts < 10) {
			OMEIS_ReportError (method, "PixelsID", ID,"ROI improperly formed.  Expected x0,y0,z0,c0,t0,x1,y1,z1,c1,t1");
			return (-1);
		}

		if (! (thePixels = GetPixelsRep (ID,rorw,iam_BigEndian)) ) {
			OMEIS_ReportError (method, "PixelsID", ID, "GetPixelsRep failed.");
			return (-1);
		}

		head = thePixels->head;
		if (!CheckCoords (thePixels, x0, y0, z0, c0, t0)){
			OMEIS_ReportError (method, "PixelsID", ID, "Parameters x0, y0, z0, c0, t0"
								" (%d,%d,%d,%d,%d) must be in range (%d,%d,%d,%d,%d).",
								x0,y0,z0,c0,t0,head->dx-1,head->dy-1,head->dz-1,head->dc-1,head->dt-1);
			freePixelsRep (thePixels);
			return (-1);
		}
		if (!CheckCoords (thePixels, x1, y1, z1, c1, t1)){
			OMEIS_ReportError (method, "PixelsID", ID, "Parameters x1, y1, z1, c1, t1"
								" (%d,%d,%d,%d,%d) must be in range (%d,%d,%d,%d,%d).",
								x1,y1,z1,c1,t1,head->dx-1,head->dy-1,head->dz-1,head->dc-1,head->dt-1);
			freePixelsRep (thePixels);
			return (-1);
		}

		if (rorw == 'w')
			thePixels->IO_stream = openInputFile(filename,isLocalFile);
		else {
			thePixels->IO_stream = stdout;
			HTTP_ResultType ("application/octet-stream");
		}
		nIO = DoROI (thePixels,x0,y0,z0,c0,t0,x1,y1,z1,c1,t1, rorw);
		if (rorw == 'w') {
			closeInputFile(thePixels->IO_stream,isLocalFile);
			HTTP_ResultType ("text/plain");
			fprintf (stdout,"%ld\n", (long) nIO);
		}
		freePixelsRep (thePixels);
	}



	return (1);
}

static
void usage (void) {

	OMEIS_ReportError ("Initialization",NULL, (OID)0, "Bad usage.  Missing parameters.");
}
int main (int argc,char **argv) {
char isCGI=0;
char **in_params;

	if (chdir (OMEIS_ROOT)) {
		OMEIS_ReportError ("Initialization",NULL, (OID)0, "Could not change working directory to %s: %s",
			OMEIS_ROOT,strerror (errno));
		exit (-1);
	}
	in_params = getCLIvars(argc,argv) ;
	if( !in_params ) {
		in_params = getcgivars() ;
		if( !in_params ) {
			usage() ;
			exit (-1) ;
		} else	isCGI = 1 ;
	} else	isCGI = 0 ;

	if (dispatch (in_params))
		return (0);
	else
		exit (-1);
}
