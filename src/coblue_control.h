//
//  coblue_control.h
//  coblue-control
//
//  Created by huke on 2/4/17.
//  Copyright (c) 2017 com.cocoahuke. All rights reserved.
//

#ifndef coblue_control_h
#define coblue_control_h

#include <pthread/pthread.h>
#include <readline/readline.h>
#include <sys/stat.h>

#define COBLUE_DEBUG_OUTPUT 0

#define COBLUE_LIST_SCANNED_DEVICES 0

extern char *COBLUE_DEVICE_NAME;

#define COBLUE_ENABLE_VERIFICATION 1
extern char *COBLUE_VERIFY_KEY;

/*return 1 when occur error*/
int coblue_terminal(char *cmd);
int coblue_fileTransfer_get(char *remotepath,char* localpath);
int coblue_fileTransfer_read(char *remotepath);
int coblue_fileTransfer_put(char *localpath,char* remotepath);
void coblue_quit();
#endif
