//
//  LEFullTextEngineTests.m
//  LEFullTextEngineTests
//
//  Created by Leo on 16/7/28.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <LEFullTextEngine/LEFullTextEngine.h>
#import "LEFTSQLDataImporter.h"
#import <Foundation/Foundation.h>

@interface NSMutableString (XMLEscape)

- (NSMutableString *)xmlSimpleUnescape;
- (NSMutableString *)xmlSimpleEscape;

@end

@implementation NSMutableString (XMLEscape)

- (NSMutableString *)xmlSimpleUnescape
{
    [self replaceOccurrencesOfString:@"&amp;"  withString:@"&"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&#x27;" withString:@"'"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&#39;"  withString:@"'"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&#x92;" withString:@"'"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&#x96;" withString:@"-"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&gt;"   withString:@">"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"&lt;"   withString:@"<"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    
    return self;
}

- (NSMutableString *)xmlSimpleEscape
{
    [self replaceOccurrencesOfString:@"&"  withString:@"&amp;"  options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"'"  withString:@"&#x27;" options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@">"  withString:@"&gt;"   options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    [self replaceOccurrencesOfString:@"<"  withString:@"&lt;"   options:NSLiteralSearch range:NSMakeRange(0, [self length])];
    
    return self;
}

@end

@implementation NSString (XMLEscapge)

- (NSString *)xmlSimpleUnescapeString
{
    NSMutableString *unescapeStr = [NSMutableString stringWithString:self];
    
    return [unescapeStr xmlSimpleUnescape];
}


- (NSString *)xmlSimpleEscapeString
{
    NSMutableString *escapeStr = [NSMutableString stringWithString:self];
    
    return [escapeStr xmlSimpleEscape];
}

@end

@interface LEFullTextEngineTests : XCTestCase

@property (nonatomic, strong) LEFullTextEngine *fulltextEngine;
@property (nonatomic, strong) LEFTSQLDataImporter *imImporter;
@property (nonatomic, strong) LEFTSQLDataImporter *sysImporter;
@property (nonatomic, strong) LEFTSQLDataImporter *tmImporter;

@end

@implementation LEFullTextEngineTests

- (void)setUp {
    [super setUp];
    clock_t begin = clock();
    self.fulltextEngine = [[LEFullTextEngine alloc] init];
    NSLog(@"init time use %lf", (double)(clock() - begin)/CLOCKS_PER_SEC);
    
    self.imImporter = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    __weak typeof(self.imImporter) weakImport = self.imImporter;
    self.imImporter.dbPath = @"/Users/Leo/Documents/imchatdb/immsghis.db";
    self.imImporter.importProcess = ^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:@"SELECT * FROM instantmsg"];
        //            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
        NSUInteger i = 0;
        while ([set next]) {
            LEFTValue *value = [[LEFTValue alloc] init];
            value.identifier = [NSString stringWithFormat:@"msg_%ld", [set longForColumn:@"guuid"]];
            value.type = 1;
            value.updateTime = [set longForColumn:@"dtime"];
            NSString *content = [set stringForColumn:@"content"];
            value.content = [content length] > 128 ? @"" : [content xmlSimpleEscapeString];
            value.tag = [set stringForColumn:@"uid"];
            value.userInfo = @{@"remoteUser": value.tag};
            
            [weakImport.engine importValuesSync:@[value]];
            i++;
            //            NSLog(@"msg import value <%@>", value);
        }
        NSLog(@"finish im block <><%zd><>", i);
    };
    
    self.sysImporter = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    weakImport = self.sysImporter;
    self.sysImporter.dbPath = @"/Users/Leo/Documents/imchatdb/sysmsghis.db";
    self.sysImporter.importProcess = ^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:@"SELECT * FROM systemmsg"];
        //            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
        NSUInteger i = 0;
        while ([set next]) {
            LEFTValue *value = [[LEFTValue alloc] init];
            value.identifier = [NSString stringWithFormat:@"sys_%ld", [set longForColumn:@"guuid"]];
            value.type = 2;
            value.updateTime = [set longForColumn:@"dtime"];
            NSString *content = [set stringForColumn:@"contentex"];
            value.content = [content length] > 128 ? @"" : [content xmlSimpleEscapeString];
            value.tag = [set stringForColumn:@"uid"];
            value.userInfo = @{@"remoteUser": value.tag};
            
            [weakImport.engine importValuesSync:@[value]];
            i++;
            //            NSLog(@"sys import value <%@>", value);
        }
        NSLog(@"finish sys block <><%zd><>", i);
    };
    
    self.tmImporter = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    weakImport = self.tmImporter;
    self.tmImporter.dbPath = @"/Users/Leo/Documents/imchatdb/tmmsghis.db";
    self.tmImporter.importProcess = ^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:@"SELECT * FROM tribemsg"];
        //            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
        NSUInteger i = 0;
        while ([set next]) {
            LEFTValue *value = [[LEFTValue alloc] init];
            value.identifier = [NSString stringWithFormat:@"tm_%ld", [set longForColumn:@"guuid"]];
            value.type = 3;
            value.updateTime = [set longForColumn:@"dtime"];
            NSString *content = [set stringForColumn:@"content"];
            value.content = [content length] > 128 ? @"" : [content xmlSimpleEscapeString];
            value.tag = [set stringForColumn:@"roomid"];
            value.userInfo = @{@"roomId": value.tag};
            
            [weakImport.engine importValuesSync:@[value]];
            i++;
            //            NSLog(@"tribe import value <%@>", value);
        }
        NSLog(@"finish tm block <><%zd><>", i);
    };

}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
//    NSFileManager *fileManager = [NSFileManager defaultManager];
//    [fileManager removeItemAtPath:self.fulltextEngine.rootDirectory error:nil];
    [super tearDown];
}

- (void)testStaticPerformance
{
//    while (YES) {
//        NSRunLoop *runloop = [NSRunLoop currentRunLoop];
//        [runloop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
//    }
}

- (void)testImport {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
//    [self.fulltextEngine startImporter:self.imImporter];
//    [self.fulltextEngine startImporter:self.sysImporter];
//    [self.fulltextEngine startImporter:self.tmImporter];
//    
//    while ([self.imImporter status] != LEFTDataImporterStatusFinished ||
//           [self.sysImporter status] != LEFTDataImporterStatusFinished ||
//           [self.tmImporter status] != LEFTDataImporterStatusFinished) {
//        NSRunLoop *runloop = [NSRunLoop currentRunLoop];
//        [runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
//    }
}

- (void)testParticiple
{
    NSString *content = @"hello你好呀world";
    NSArray *words = [[self.fulltextEngine partcipleWrapper] minimumTestParticipleContent:content];
    NSLog(@"content is %@, words is %@", content, words);
    words = [[self.fulltextEngine partcipleWrapper] participleKeywordsContent:content];
    NSLog(@"content is %@, full words is %@", content, words);
    
    content = @"lllb太难cnntm你什么dongxi网易中国研究院在杭州";
    
    words = [[self.fulltextEngine partcipleWrapper] minimumTestParticipleContent:content];
    NSLog(@"content is %@, words is %@", content, words);
    words = [[self.fulltextEngine partcipleWrapper] participleKeywordsContent:content];
    NSLog(@"content is %@, full words is %@", content, words);
}

- (void)testSearch
{
    __block BOOL finish = NO;
    [self.fulltextEngine searchValueWithKeywords:@[@"一个"] until:1000000 resultHandler:^(LEFTSearchResult *result) {
        LEFTValue *value = [result next];
        NSUInteger i = 0;
        while (value) {
            NSLog(@"..... %@", value);
            i++;
            value = [result next];
        }
        finish = YES;
    }];
    while (!finish) {
        NSRunLoop *runloop = [NSRunLoop currentRunLoop];
        [runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
}

- (void)testDelete
{
    LEFTValue *value = [[LEFTValue alloc] init];
    value.keywords = @[@"一个"];
    value.identifier = @"tm_6052932614138918611";
    value.type = 3;
    [self.fulltextEngine deleteWithValue:value];
}

@end
