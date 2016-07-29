//
//  LEFTSQLDataImporter.m
//  FullTextSearch
//
//  Created by Leo on 16/6/12.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFTSQLDataImporter.h"
#import "LEFTValue.h"
#import "LEFullTextEngine_Class.h"

@interface LEFTSQLDataImporter ()

@property (nonatomic, weak) LEFullTextEngine *engine;

@end

@implementation LEFTSQLDataImporter

@synthesize status = _status;

- (instancetype)initWithEngine:(LEFullTextEngine *)engine
{
    if (self = [super init]) {
        self.engine = engine;
        self.status = LEFTDataImporterStatusPending;
    }
    return self;
}

- (void)start
{
    NSLog(@"start import sql data in thread <%@>", [NSThread currentThread]);
    self.status = LEFTDataImporterStatusRunning;
    if (self.importProcess != NULL) {
        FMDatabase *database = [[FMDatabase alloc] initWithPath:self.dbPath];
        if ([database open]) {
            self.importProcess(database);
        }
        [database close];
    }
    NSLog(@"finish import sql data in thread <%@>", [NSThread currentThread]);
    self.status = LEFTDataImporterStatusFinished;
}

- (void)pause
{
    self.status = LEFTDataImporterStatusFinished;
}

- (void)cancel
{
    self.status = LEFTDataImporterStatusFinished;
}

- (void)stop
{
    self.status = LEFTDataImporterStatusFinished;
}

@end
