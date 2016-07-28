//
//  LEFTSQLDataImporter.m
//  FullTextSearch
//
//  Created by Leo on 16/6/12.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFTSQLDataImporter.h"
#import "LEFTValue.h"
#import "LEFullTextEngine.h"

@interface LEFTSQLDataImporter ()

@property (nonatomic, weak) LEFullTextEngine *engine;

@end

@implementation LEFTSQLDataImporter

@synthesize status = _status;

- (instancetype)initWithEngine:(LEFullTextEngine *)engine
{
    if (self = [super init]) {
        self.engine = engine;
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
    {
        FMDatabase *database = [[FMDatabase alloc] initWithPath:@"/Users/Leo/Documents/imchatdb/immsghis.db"];
        if ([database open]) {
            FMResultSet *set = [database executeQuery:@"SELECT * FROM instantmsg"];
//            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
            do {
                LEFTValue *value = [[LEFTValue alloc] init];
                value.identifier = [NSString stringWithFormat:@"msg_%ld", [set longForColumnIndex:0]];
                value.type = 1;
                value.content = [set stringForColumn:@"content"];
                
                [self.engine importValue:value];
                NSLog(@"import value <%@>", value);
            } while ([set next]);
            [database close];
        }
    }
//
//    {
//        FMDatabase *database = [[FMDatabase alloc] initWithPath:@"/Users/Leo/Documents/imchatdb/sysmsghis.db"];
//        if ([database open]) {
//            FMResultSet *set = [database executeQuery:@"SELECT * FROM instantmsg"];
////            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
//            do {
//                LEFTValue *value = [[LEFTValue alloc] init];
//                value.identifier = [NSString stringWithFormat:@"sysmsg_%ld", [set longForColumnIndex:0]];
//                value.type = 1;
//                value.content = [set stringForColumn:@"content"];
//                
//                [self.engine importValue:value];
//                NSLog(@"import value <%@>", value);
//            } while ([set next]);
//            [database close];
//        }
//    }
//    
//    {
//        FMDatabase *database = [[FMDatabase alloc] initWithPath:@"/Users/Leo/Documents/imchatdb/tmmsghis.db"];
//        if ([database open]) {
//            FMResultSet *set = [database executeQuery:@"SELECT * FROM tribemsg"];
////            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM tribemsg"];
//            do {
//                LEFTValue *value = [[LEFTValue alloc] init];
//                value.identifier = [NSString stringWithFormat:@"tribemsg_%ld", [set longForColumnIndex:0]];
//                value.type = 1;
//                value.content = [set stringForColumn:@"content"];
//                
//                [self.engine importValue:value];
//                NSLog(@"import value <%@>", value);
//            } while ([set next]);
//            [database close];
//        }
//    }
    NSLog(@"finish import sql data in thread <%@>", [NSThread currentThread]);
}

- (void)pause
{
    self.status = LEFTDataImporterStatusRunning;
}

- (void)cancel
{
    self.status = LEFTDataImporterStatusRunning;
}

- (void)stop
{
    self.status = LEFTDataImporterStatusRunning;
}

@end
