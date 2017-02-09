//
//  main.m
//  coblue-control
//
//  Created by huke on 2/4/17.
//  Copyright (c) 2017 com.cocoahuke. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <CoreBluetooth/CoreBluetooth.h>
#include <readline/readline.h>
#include <readline/history.h>
#include <wordexp.h>
#include <sys/select.h>
#include "coblue_control.h"

#define COLOR_OFF	"\x1B[0m"
#define COLOR_WHITE	"\x1B[0;37m"
#define COLOR_RED	"\x1B[0;91m"
#define COLOR_GREEN	"\x1B[0;92m"
#define COLOR_YELLOW	"\x1B[0;93m"
#define COLOR_BLUE	"\x1B[0;94m"
#define COLOR_MAGENTA	"\x1B[0;95m"
#define COLOR_BOLDGRAY	"\x1B[1;30m"
#define COLOR_BOLDWHITE	"\x1B[1;37m"

#define NELEM(x) (sizeof(x)/sizeof((x)[0]))

struct cmd_info {
    char *cmd;
    void (*func)(int argc, char **argv);
    char *doc;
};

void cmd_coget(int argc, char **argv){
    if (!argv[1]||!argv[2]){
        printf("Usage: %s <remotePath> <localPath>\n",argv[0]);
        return;
    }
    coblue_fileTransfer_get(argv[1],argv[2]);
}

void cmd_read(int argc, char **argv){
    if (!argv[1]){
        printf("Usage: %s <remotePath>\n",argv[0]);
        return;
    }
    coblue_fileTransfer_read(argv[1]);
}

void cmd_coput(int argc, char **argv){
    if (!argv[1]||!argv[2]){
        printf("Usage: %s <localPath> <remotePath>\n",argv[0]);
        return;
    }
    coblue_fileTransfer_put(argv[1],argv[2]);
}


void cmd_clear(int argc, char **argv){
    printf("\033[H\033[J");
}

void cmd_quit(int argc, char **argv)
{
    coblue_quit();
    exit(1);
}

void cmd_help(int argc, char **argv);
static struct cmd_info all_cmd[] = {
    { "coget", cmd_coget, "\t\tcoBlue filetransfer get operation"},
    { "coread", cmd_read, "\tcoBlue filetransfer read operation"},
    { "coput", cmd_coput, "\t\tcoBlue filetransfer put operation"},
    { "help", cmd_help, "\t\tShow all availble cmds"},
    { "clear", cmd_clear, "\t\tClear the terminal screen"},
    { "quit", cmd_quit, "\t\tExit program"},
    { "exit", cmd_quit, "\t\tExit program"}
};

void cmd_help(int argc, char **argv){
    struct cmd_info *c;
    char space = ' ';
    
    printf("coBlue console:\n");
    for (int i = 0; i < NELEM(all_cmd); i++) {
        c = &all_cmd[i];
        if (c->doc)
            printf("%-2c%s%s\n", space, c->cmd, c->doc);
    }
}

static struct cmd_info *find_cmd(const char *cmd, struct cmd_info cmds_table[], size_t cmd_count)
{
    size_t i;
    
    for (i = 0; i < cmd_count; i++) {
        if (!strcmp(cmds_table[i].cmd, cmd))
            return &cmds_table[i];
    }
    
    return NULL;
}

static char *cmd_generator(const char *text, int state)
{
    static size_t i, j, len;
    const char *cmd;
    
    if(!state){
        i = 0;
        j = 0;
        len = strlen(text);
    }
    
    while (i<NELEM(all_cmd)){
        cmd = all_cmd[i++].cmd;
        
        if(!strncmp(cmd,text,len))
            return strdup(cmd);
    }
    
    return NULL;
}

static char **cmd_completion(const char *text, int start, int end)
{
    char **matches = NULL;
    
    if(start>0){
        //when a space include don't do the completion
    }
    else{
        matches = rl_completion_matches(text,cmd_generator);
    }
    
    if(!strchr(text,'/')) //do filesystem completion when input start with /
        rl_attempted_completion_over = 1;
    return matches;
}

void execCmd(char *inputStr)
{
    struct cmd_info *c;
    wordexp_t w;
    char *cmd, **argv;
    int argc;
    
    if(wordexp(inputStr,&w,WRDE_NOCMD))
        goto send_cmd;
    
    if(w.we_wordv==0)
        goto done;
    
    cmd = w.we_wordv[0];
    argv = w.we_wordv;
    argc = (int)w.we_offs;
    
    c = find_cmd(cmd,all_cmd,NELEM(all_cmd));
    if(c){
        c->func(argc,argv);
    }
    else{
        coblue_terminal(inputStr);
    }
    
done:
    wordfree(&w);
    return;
    
send_cmd:
    coblue_terminal(inputStr);
}

int is_empty(const char *c){
    if(!c){
        printf("\n");
        return 1;
    }
    size_t len = strlen(c);
    if(!len)
        return 1;
    for(int i=0;i<len;i++)
    {
        if(!isspace(c[i]))
            return 0;
    }
    return 1;
}


int main(int argc, const char * argv[]) {
    COBLUE_DEVICE_NAME = "orange";
    COBLUE_VERIFY_KEY = "0381676B-59AE-4D05-B1CA-C350B8870B11";
    
    //readline will occur override error when with colorful prompt
    //COLOR_YELLOW "[coblue server]" COLOR_OFF "# "
    rl_attempted_completion_function = cmd_completion;
    while(1){
        char *inputStr = readline("[coblue server]# ");
        if(is_empty(inputStr)){
            goto done;
        }
        
        add_history(inputStr);
        execCmd(inputStr);
    done:
        free(inputStr);
    }
    
    return 0;
}