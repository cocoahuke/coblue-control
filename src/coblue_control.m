//
//  coblue_control.m
//  coblue-control
//
//  Created by huke on 2/4/17.
//  Copyright (c) 2017 com.cocoahuke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#include "coblue_control.h"

char *COBLUE_DEVICE_NAME = NULL;
char *COBLUE_VERIFY_KEY = NULL;

static int power_status = 0;

#define RECEIVE_SIZE 20 /*Should be same as SEND_SIZE in coblue server*/
#define SEND_SIZE 512  /*Should be same as RECEIVE_SIZE in coblue server*/

#define FILE_TRANSFER_IDLE 0x1
#define FILE_TRANSFER_NEED_RESPOND 0x2
#define FILE_TRANSFER_DECIDING_RW 0x4
#define FILE_TRANSFER_DECIDING_PATH 0x8
#define FILE_TRANSFER_READFILE_SIZE 0x10
#define FILE_TRANSFER_READING_FILE 0x20
#define FILE_TRANSFER_WRITEFILE_PATH_NAME 0x40
#define FILE_TRANSFER_WRITEFILE_SIZE 0x80
#define FILE_TRANSFER_WRITING_FILE 0x100
#define FILE_TRANSFER_ERROR_MACRO_START FILE_TRANSFER_ERROR_OP_NOT_EXIST
#define FILE_TRANSFER_ERROR_OP_NOT_EXIST 0x200
#define FILE_TRANSFER_ERROR_FILEPATH_TOO_LONG 0x400
#define FILE_TRANSFER_ERROR_LOCALFILE_NOT_EXIST 0x800
#define FILE_TRANSFER_ERROR_LOCALFILE_ALREADY_EXIST 0x1000
#define FILE_TRANSFER_ERROR_LOCALFILE_ITS_DIRECTORY 0x2000
#define FILE_TRANSFER_ERROR_LOCALFILE_ITS_EMPTY_FILE 0x4000
#define FILE_TRANSFER_ERROR_LOCALFILE_FILE_TOO_LARGE 0x8000
#define FILE_TRANSFER_ERROR_LOCALFILE_FOPEN_FAILED 0x10000
#define FILE_TRANSFER_ERROR_MACRO_END FILE_TRANSFER_ERROR_LOCALFILE_FOPEN_FAILED

@interface coblueClass : NSObject <CBCentralManagerDelegate,CBPeripheralDelegate>
@property(strong,nonatomic) CBCentralManager* central;
@property(strong,nonatomic) CBPeripheral* peri_coblue;
@property(strong,nonatomic) CBService *service_coblue;
@property(strong,nonatomic) CBCharacteristic* charc_terminal;
@property(strong,nonatomic) CBCharacteristic* charc_filetransfer;
-(void)coblue_quit;
-(void)coblue_verification:(CBCharacteristic*)cbchar;
-(char*)charc_terminal_read;
-(void)charc_terminal_write:(void*)data length:(uint32_t)length;
-(void)coblue_filetransfer_put:(NSString*)localpath remotepath:(NSString*)remotepath;
-(void)coblue_filetransfer_get:(NSString*)remotepath localpath:(NSString*)localpath onlyPrintit:(BOOL)onlyPrintit;
@end
coblueClass *coblue = NULL;
@implementation coblueClass
{
    const void *readop_return;int readop_done;
    int writeop_done;
    int done_verify;
}

void cus_progress(uint32_t cur,uint32_t total){
    int len = 50;
    cur = len*((double)cur/(double)total);
    printf("[");
    int pos = cur;
    for (int i = 0; i < len; ++i) {
        if (i < pos) printf("#");
        else printf(" ");
    }
    printf("] %d%%\r",cur*2);
    fflush(stdout);
}

-(instancetype)init{
    self = [super init];
    dispatch_queue_t centralQueue = dispatch_queue_create("coblueCentralQueue",DISPATCH_QUEUE_SERIAL);
    self.central = [[CBCentralManager alloc]initWithDelegate:self queue:centralQueue options:nil];
    self.central.delegate = self;
    return self;
}

-(void)coblue_quit{
    if(self.central){
        [self.central stopScan];
        if(self.peri_coblue)
            [self.central cancelPeripheralConnection:self.peri_coblue];
            kill(getpid(),SIGKILL);
    }
}

-(void)coblue_verification:(CBCharacteristic *)cbchar{
    if(COBLUE_ENABLE_VERIFICATION&&!done_verify){
        [self.peri_coblue writeValue:[[NSString stringWithUTF8String:COBLUE_VERIFY_KEY]dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:cbchar type:CBCharacteristicWriteWithoutResponse];
        done_verify = 1;
    }
}

-(char*)charc_terminal_read{
    readop_return = NULL;readop_done=0;
    [self.peri_coblue readValueForCharacteristic:self.charc_terminal];
    while(!readop_done){
        
    }
    return (char*)readop_return;
}

-(void)charc_terminal_write:(void*)data length:(uint32_t)length{
    writeop_done = 0;
    [self.peri_coblue writeValue:[NSData dataWithBytes:data length:length] forCharacteristic:self.charc_terminal type:CBCharacteristicWriteWithoutResponse];
    while(!writeop_done){
        
    }
}

-(int)coblue_filetransfer_check_error:(uint32_t)status{
    int i = FILE_TRANSFER_ERROR_MACRO_START;
    for(;i<=FILE_TRANSFER_ERROR_MACRO_END;i=i*2){
        if(status&i){
            printf("coblue filetransfer error: 0x%x\n",status);
            return 1;
        }
    }
    return 0;
}

-(char*)charc_filetransfer_read{
    readop_return = NULL;readop_done=0;
    [self.peri_coblue readValueForCharacteristic:self.charc_filetransfer];
    while(!readop_done){
        
    }
    return (char*)readop_return;
}

-(void)charc_filetransfer_write:(NSData*)data{
    writeop_done = 0;
    if(data)
        [self.peri_coblue writeValue:data forCharacteristic:self.charc_filetransfer type:CBCharacteristicWriteWithoutResponse];
    else
        [self.peri_coblue writeValue:[NSData dataWithBytes:&writeop_done length:0] forCharacteristic:self.charc_filetransfer type:CBCharacteristicWriteWithoutResponse];
    
    while(!writeop_done){
        
    }
}

-(void)coblue_filetransfer_put:(NSString*)localpath remotepath:(NSString*)remotepath{
    const char *filepath;
    FILE *filefp=NULL;
    char *filebuf;
    size_t filesize=0;
    size_t wrotesize = 0;
    struct stat fstat;
    int cur=1,total=0;
    
    filepath = [localpath UTF8String];
    
    if(access(filepath,F_OK)){
        printf("put: file is not exist\n");return;
    }
    
    if(access(filepath,R_OK)){
        printf("put: file is not able to read\n");return;
    }
    
    stat(filepath,&fstat);
    
    if(fstat.st_size>UINT32_MAX){
        printf("put: file too large\n");return;
    }
    
    filesize = (uint32_t)fstat.st_size;
    char tmpbuf[filesize];
    filebuf = tmpbuf;
    
    filefp = fopen(filepath,"ro");
    if(!filefp){
        printf("put: fopen failed\n");return;
    }
    
    printf("filesize:%zu\n",filesize);
    
    if(fread(filebuf,1,filesize,filefp)!=filesize){
        printf("put: fread failed\n");goto done;
    }
    
    if([self coblue_filetransfer_check_error:*(uint32_t*)[self charc_filetransfer_read]]) goto done;
    /*Step 1: Check isit filetransfer available*/
    
    [self charc_filetransfer_write:[@"write" dataUsingEncoding:NSUTF8StringEncoding]];
    /*Step 2: decide read/write operate*/
    
    if([self coblue_filetransfer_check_error:*(uint32_t*)[self charc_filetransfer_read]]) goto done;
    /*Step 3: check that decide operate is valid*/
    
    
    [self charc_filetransfer_write:[remotepath dataUsingEncoding:NSUTF8StringEncoding]];
    /*Step 4: decide filepath*/
    
    if([self coblue_filetransfer_check_error:*(uint32_t*)[self charc_filetransfer_read]]) goto done;
    /*Step 5: check that file is able to write*/
    
    total = (int)(filesize/SEND_SIZE + (filesize%SEND_SIZE?1:0));
    
    /*Step 6: start writing*/
    for(;filesize>0;cur++){
        cus_progress(cur,total);
        wrotesize = filesize>SEND_SIZE?SEND_SIZE:filesize;
        [self charc_filetransfer_write:[NSData dataWithBytes:filebuf length:wrotesize]];
        filesize-=wrotesize;
        filebuf+=wrotesize;
    }
    
    [self charc_filetransfer_write:NULL];
    printf("\n");
    printf("put: Complete\n");
done:
    if(filefp>0) fclose(filefp);
}

-(void)coblue_filetransfer_get:(NSString*)remotepath localpath:(NSString*)localpath onlyPrintit:(BOOL)onlyPrintit{
    FILE *filefp = NULL;
    uint32_t filesize = 0;
    size_t readsize = 0;
    int cur=1,total=0;
    
    if(!onlyPrintit){
        if([[NSFileManager defaultManager] fileExistsAtPath:localpath]){
            printf("get:in %s a file or directory is already exist\n",[localpath UTF8String]);
            return;
        }
        
        filefp = fopen([localpath UTF8String],"a+");
        if(!filefp){
            perror("get:cannot create localfile");return;
        }
    }
    
    if([self coblue_filetransfer_check_error:*(uint32_t*)[self charc_filetransfer_read]]) goto err_done;
    /*Step 1: Check isit filetransfer available*/
    
    [self charc_filetransfer_write:[@"read" dataUsingEncoding:NSUTF8StringEncoding]];
    /*Step 2: decide read/write operate*/
    
    if([self coblue_filetransfer_check_error:*(uint32_t*)[self charc_filetransfer_read]]) goto err_done;
    /*Step 3: check that decide operate is valid*/
    
    
    [self charc_filetransfer_write:[remotepath dataUsingEncoding:NSUTF8StringEncoding]];
    /*Step 4: decide filepath*/
    
    if([self coblue_filetransfer_check_error:*(uint32_t*)[self charc_filetransfer_read]]) goto err_done;
    /*Step 5: check that file is able to read*/
    
    filesize = *(uint32_t*)[self charc_filetransfer_read];
    /*Step 6: get file size for read*/
    
    if(!filesize){
        printf("get:filesize cannot be zero\n");if(filefp) fclose(filefp);return;
    }
    
    printf("filesize:%d\n",filesize);
    total = (filesize/RECEIVE_SIZE) + (filesize%RECEIVE_SIZE?1:0);
    
    
    if(onlyPrintit)
        printf("---FOLLOWING_CONTENT_START---\n");
    
    /*Step 7: start reading*/
    for(char *buf=NULL;filesize>0;cur++){
        if(onlyPrintit){
            readsize = filesize<=RECEIVE_SIZE?filesize:RECEIVE_SIZE;
            buf=[coblue charc_filetransfer_read];
            printf("%s",buf);
            filesize-=readsize;
        }
        else{
            cus_progress(cur,total);
            readsize = filesize<=RECEIVE_SIZE?filesize:RECEIVE_SIZE;
            buf=[coblue charc_filetransfer_read];
            fwrite(buf,1,readsize,filefp);
            filesize-=readsize;
        }
    }
    
    if(onlyPrintit)
        printf("\n---CONTENT_END---\n");
    
    [coblue charc_filetransfer_read];
    if(!onlyPrintit)
        printf("\n");
    fclose(filefp);
    printf("get: Complete\n");
    return;
err_done:
    if(filefp>0) fclose(filefp);
    unlink([localpath UTF8String]);
}

-(void)centralManagerDidUpdateState:(CBCentralManager *)central{
    power_status = central.state;
    if(central.state !=  CBCentralManagerStatePoweredOn){
        return;
    }
    
    [central scanForPeripheralsWithServices:nil options:nil];
}

-(void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI{
    
    if(COBLUE_LIST_SCANNED_DEVICES)
        printf("%s %s %d\n",[[[peripheral identifier]UUIDString] UTF8String],[[peripheral name] UTF8String]?[[peripheral name] UTF8String]:"[UNKNOWN]",[RSSI intValue]);
    
    if([[peripheral name] isEqualToString:[NSString stringWithUTF8String:COBLUE_DEVICE_NAME]]){
        
        [_central stopScan];
        self.peri_coblue = peripheral;
        peripheral.delegate = self;
        [central connectPeripheral:peripheral options:nil];
    }
}

-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral{
    printf("connected\n");
    if(COBLUE_ENABLE_VERIFICATION)
        done_verify = 0;
    [peripheral discoverServices:nil];
}

-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error{
    printf("device[%s] Disconnect\n",[[[peripheral identifier] UUIDString] UTF8String]);
    kill(getpid(),SIGKILL);
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error{
    for(int i=0;i<[[peripheral services]count];i++){
        CBService *service = [peripheral services][i];
        //printf("service [%s]\n",[[[service UUID] UUIDString] UTF8String]);
        if([[[service UUID] UUIDString] isEqualToString:@"1111"]){
            self.service_coblue = service;
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error{
    //printf("%lu characteristics\n",(unsigned long)[[service characteristics] count]);
    for(int i=0;i<[[service characteristics] count];i++){
        CBCharacteristic *each_charc = [service characteristics][i];
        [self coblue_verification:each_charc];
        if([[[each_charc UUID] UUIDString] isEqualToString:@"2222"]){
            self.charc_terminal = each_charc;
        }
        else if([[[each_charc UUID] UUIDString] isEqualToString:@"3333"]){
            self.charc_filetransfer = each_charc;
        }

    }
}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    if(error){
        NSLog(@"read failed:%@",error);
    }
    //NSLog(@"%lu",(unsigned long)characteristic.value.length);
    readop_return = [characteristic.value bytes];readop_done = 1;
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    if(error){
        NSLog(@"write failed:%@",error);
    }
    writeop_done = 1;
}

@end

int alloccoblue(){
    
    if(!coblue){
        printf("scanning device (name:%s)...\n",COBLUE_DEVICE_NAME);
        
        if(!COBLUE_DEVICE_NAME){
            printf("please specified device name\n");return 1;
        }
        
        if(COBLUE_ENABLE_VERIFICATION&&!COBLUE_VERIFY_KEY){
            printf("please specified verify key\n");return 1;
        }
        
        coblue = [[coblueClass alloc]init];
        while(!power_status){}
        if(power_status&&power_status!=CBCentralManagerStatePoweredOn){
            printf("bluetooth device unavailable\n");return 1;
        }
        
        while(!coblue.peri_coblue){
            
        }
        //printf("coblue Peripheral found!\n");
        printf("Init Step (1/4)\n");
        while(!coblue.service_coblue){
        
        }
        //printf("coblue Service found!\n");
        printf("Init Step (2/4)\n");
        while(!coblue.charc_terminal){
            
        }
        //printf("Terminal Characteristic found!\n");
        printf("Init Step (3/4)\n");
        while(!coblue.charc_filetransfer){
            
        }
        //printf("FileTransfer Characteristic found!\n");
        printf("Init Step (4/4)\nInit Cmplt\n");
    }
    return 0;
}

int coblue_terminal(char *cmd)
{
    if(alloccoblue()) exit(1);
    
    if(strlen(cmd)>UINT32_MAX){
        printf("ENTER TOO LONG\n");return 1;
    }
    
    [coblue charc_terminal_write:cmd length:(uint32_t)strlen(cmd)];
    [coblue charc_terminal_read];
    for(char *a;(a=[coblue charc_terminal_read]);){
        printf("%s",a);
    }
    
    return 0;
}

int coblue_fileTransfer_get(char *remotepath,char* localpath)
{
    if(alloccoblue()) return 1;
    [coblue coblue_filetransfer_get:[NSString stringWithUTF8String:remotepath] localpath:[NSString stringWithUTF8String:localpath] onlyPrintit:NO];
    return 0;
}

int coblue_fileTransfer_read(char *remotepath){
    if(alloccoblue()) return 1;
    [coblue coblue_filetransfer_get:[NSString stringWithUTF8String:remotepath] localpath:NULL onlyPrintit:YES];
    return 0;
}

int coblue_fileTransfer_put(char *localpath,char* remotepath)
{
    if(alloccoblue()) return 1;
    [coblue coblue_filetransfer_put:[NSString stringWithUTF8String:localpath] remotepath:[NSString stringWithUTF8String:remotepath]];
    return 0;
}

void coblue_quit()
{
    [coblue coblue_quit];
}
