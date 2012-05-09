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
 * Written by:	Michael Hlavenka <mthlavenka@wisc.edu> 11/2005
 *
 *------------------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

#include "OMEIS_Error.h"
#include "Pixels.h"
#include "omeis.h"
#include "archive.h"

#ifndef OMEIS_ROOT
#define OMEIS_ROOT "."
#endif

int 
zipFiles(char **param) {
  char *paramPiece;
  OID *zipFileID;
  OID fileID;
  OID ID=0;
  int offset = 0;
  int length = 0;
  int num_files = 0;
  char *file_path;
  char *temp_path;
  char *orig_path;
  char *symlink_path;
  char *zip_path;
  char *file_name;
  char *zip_cmd = "zip -j -q ";
  char *old_zip_cmd;
  char *orig_name;
  FILE *zip_file;
  DIR* tmp_dir;
  struct dirent *tmp_entry;
  char *byteBuf = malloc(BUF_SIZE);
  int error_happened = 0;
  int i;
  unsigned long long scan_ID;
  char *theParam;
  char *method = "ZipFiles";

  file_path = malloc(MAX_PATH_LENGTH);
  strcpy(file_path, "Files/");
  
  // switch for convenience of break
  switch (0) { 
    case 0:
    // Getting the FileID parameter
    if ( (theParam = get_param(param,"FileID")) ) {
      zipFileID = malloc(sizeof(OID) * strlen(theParam));
      paramPiece = strtok(theParam, ",");
      while (paramPiece != NULL) {
	sscanf (paramPiece,"%llu",&scan_ID);
	zipFileID[num_files] = (OID)scan_ID;
	paramPiece = strtok(NULL, ",");
	num_files++;
      }
    } else {
      OMEIS_ReportError (method, NULL, ID,"FileID must be specified!");
      error_happened = 1;
      break;
    }
    
    // Getting the Original Name parameter
    if ( (theParam = get_param (param,"OrigName")) ) {
      orig_name = theParam;
    }
    else {
      orig_name = "images";
    }
    
    //Creating the temporary directory
    temp_path = malloc(strlen(OMEIS_ROOT)+1+strlen(file_path)+strlen("tmp.XXXXXX")+1);
    strcpy(temp_path, OMEIS_ROOT);
    strcat(temp_path,"/");
    strcat(temp_path,file_path);
    strcat(temp_path,"tmp.XXXXXX");

    // The "XXXXXX" of the tmp directory will be filled with random chars
    if (mkdtemp(temp_path) == NULL) {
      OMEIS_ReportError(method, NULL, ID,"Temporary directory could not be created");
      error_happened = 1;
      break;
    }
    
    // Adding the original name to the zip command
    old_zip_cmd = zip_cmd;
    zip_cmd = malloc(strlen(old_zip_cmd)+strlen(temp_path)+1+strlen(orig_name)+strlen(".zip ")+1);
    strcpy(zip_cmd, old_zip_cmd);
    strcat(zip_cmd, temp_path);
    strcat(zip_cmd, "/");
    strcat(zip_cmd, orig_name);
    strcat(zip_cmd, ".zip ");

    for (i = 0; i < num_files; i++) {
      fileID = zipFileID[i];
      strcpy(file_path, "Files/");
      if (! getRepPath (fileID,file_path,0)) {
	OMEIS_ReportError (method, "FileID", fileID, "getRepPath failed");
	error_happened = 1;
	break;
      }
      
      //Constructing the Full local path of the original image file
      orig_path = malloc(strlen(OMEIS_ROOT) + 1 + strlen(file_path) + 1);
      strcpy(orig_path, OMEIS_ROOT);
      strcat(orig_path, "/");
      strcat(orig_path, file_path);
      
      //Constructing the new symlink path
      file_name = GetFileRep(fileID,0,0)->file_info.name;
      symlink_path = malloc(strlen(temp_path) + 1 + strlen(file_name) + 1);
      strcpy(symlink_path,temp_path);
      strcat(symlink_path,"/");
      strcat(symlink_path,file_name);
      
      //Adding to the zip command
      old_zip_cmd = zip_cmd;
      zip_cmd = malloc(strlen(old_zip_cmd) + 1 + strlen(symlink_path) + 1);
      strcpy(zip_cmd, old_zip_cmd);
      strcat(zip_cmd, " ");
      strcat(zip_cmd, symlink_path);
      
      if (symlink(orig_path, symlink_path)) {
	OMEIS_ReportError (method, "FileID", fileID, "symlink failed");
	error_happened = 1;
	free(orig_path);
	free(symlink_path);
	free(old_zip_cmd);
	break;
      }
      free(orig_path);
      free(symlink_path);
      free(old_zip_cmd);
    }
    
    // Test if an error happened
    if (error_happened) break;
    
    // System call: Does the actual zipping
    if (system(zip_cmd)) {
      OMEIS_ReportError(method, NULL, ID, "system call failed");
      error_happened = 1;
      break;
    }
    
    // Printing the Zip file to the browser
    zip_path = malloc(strlen(temp_path) + 1 + strlen(orig_name) + strlen(".zip") + 1);
    strcpy(zip_path, temp_path);
    strcat(zip_path, "/");
    strcat(zip_path, orig_name);
    strcat(zip_path, ".zip");
    if ((zip_file = fopen(zip_path, "r")) == NULL) {
      OMEIS_ReportError(method, NULL, ID, "zip file open failed");
      error_happened = 1;
      break;
    }
    
    if (getenv("REQUEST_METHOD") ) {
      fprintf (stdout,"Content-Disposition: attachment; filename=\"%s.zip\"\r\n",orig_name);
    }
    
    HTTP_ResultType ("application/octet-stream");
        
    while ((i = fread(byteBuf,1, BUF_SIZE, zip_file)) > 0){
      fwrite ((u_int8_t *)byteBuf,1,i,stdout);
    }
    
    
  }

  // CLEANUP
  //Clearing out the directory and deleting it
  tmp_dir = opendir(temp_path);
  orig_path = malloc(strlen(temp_path) + NAME_LIMIT);
  strcpy(orig_path, temp_path);
  strcat(orig_path, "/");
  
  file_name = orig_path + strlen(temp_path) + 1;
  

  // Remove temporary files in the tmp directory
  while ((tmp_entry = readdir(tmp_dir)) != NULL) {
    if (strcmp(tmp_entry->d_name, ".") && strcmp(tmp_entry->d_name,"..")) {
      strcpy(file_name, tmp_entry->d_name);
      if (unlink(orig_path)) {
	OMEIS_ReportError(method, NULL, ID, "Temporary files were not removed");
	error_happened = 1;
	break;
      }
    }
  }

  // Removing the tmp directory
  rmdir(temp_path);
  
  // Freeing up the memory
  if (zipFileID) free(zipFileID);
  if (zip_cmd) free(zip_cmd);
  if (zip_path) free(zip_path);
  if (temp_path) free(temp_path);
  
  if (error_happened) 
    return -1;
  
  else 
    return 0;

}
