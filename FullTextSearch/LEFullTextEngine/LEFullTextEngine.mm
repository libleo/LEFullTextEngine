//
//  LEFullTextEngine.m
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFullTextEngine.h"
#import "LEFTValue.h"

#include "json.h"

#define DB_SUFFIX @"idxdb"
#define CURRENT_MAIN_DB_VER @"0.1"

#define TEST_TABLE_EXIST @"SELECT name FROM sqlite_master WHERE type='table' AND name='%@';"
#define CREATE_KEYWORD_TABLE_0_1 @"CREATE TABLE IF NOT EXISTS `%@` (idf TEXT NOT NULL, type INTEGER NOT NULL, updatetime INTEGER NOT NULL, content TEXT, userinfo TEXT);"
#define INSERT_KEYWORD_QUERY @"INSERT INTO `%@` (idf, type, updatetime, content, userinfo) VALUES (\"%s\", %d, %ld, \"%s\", \"%s\");"
#define UPDATE_KEYWORD_QUERY @"UPDATE `%@` SET content=\"%s\", userinfo=\"\%s\" WHERE idf=\"%s\" AND type=%d;"
#define CHECK_VALUE_ISEXIST @"SELECT `rowid`, `idf`, `type` FROM `%@` WHERE idf=\"%s\" AND type=%d;"

// 模式切换
#define RUNLOOP_M1 1
//#define RUNLOOP_M2 1
//#define GCD_M 1

// 目前没有加密功能

/*
 * 关键字 作为 tablename
 * table schema [identifier(str128), type(int), updatetime(timestamp), content(str512), userinfo(string)]
 *
 */

@interface LEFullTextEngine ()
{
    sqlite3 *_write_db;
    sqlite3 *_read_db;
}

@property (nonatomic, copy) NSString *rootDirectory;

@property (nonatomic, strong) LEFTPartcipleWrapper *partcipleWrapper;
@property (nonatomic, strong) NSMutableArray *dataImporters;
@property (nonatomic, strong) NSOperationQueue *importQueue;

@property (nonatomic, strong) NSMutableArray *importValues;

@property (nonatomic, strong) NSThread *importThread;
@property (assign) BOOL stopImportThread;

@end

@implementation LEFullTextEngine

@synthesize partcipleWrapper = _partcipleWrapper;
@synthesize rootDirectory = _rootDirectory;

- (void)dealloc
{
    
}

- (instancetype)init
{
    if (self = [super init]) {
        NSArray *tmpArray = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        // 如果一个用户目录都不能用，还是crash吧
        NSString *bundleIdentifer = [[NSBundle mainBundle] bundleIdentifier];
        self.rootDirectory = [[tmpArray objectAtIndex:0] stringByAppendingPathComponent:bundleIdentifer];
        [self _init];
    }
    return self;
}

- (instancetype)initWithRootDirectory:(NSString *)rootDirectory
{
    if (self = [super init]) {
        self.rootDirectory = rootDirectory;
        [self _init];
    }
    return self;
}

- (void)_init
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    BOOL res = [fileManager fileExistsAtPath:self.rootDirectory isDirectory:&isDir];
    if (res) {
        if (!isDir) {
            @throw [NSException exceptionWithName:@"Root Path Error" reason:@"Need A directory" userInfo:@{}];
        }
    } else {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:self.rootDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            @throw [NSException exceptionWithName:@"Root Path Error" reason:[error localizedDescription] userInfo:@{@"error": error}];
        }
    }
    
    self.partcipleWrapper = [[LEFTPartcipleWrapper alloc] init];
    self.dataImporters = [NSMutableArray array];
    self.importQueue = [[NSOperationQueue alloc] init];
    
    self.importQueue.maxConcurrentOperationCount = 1;
    [self.importQueue setSuspended:NO];
    
    const char *db_path = [[self _dbNameWithName:@"main"] cStringUsingEncoding:NSUTF8StringEncoding];
    res = sqlite3_open(db_path, &_write_db);
    if (res != 0) {
        NSLog(@"open write db failed <%s>", strerror(errno));
    }
    res = sqlite3_open(db_path, &_read_db);
    if (res != 0) {
        NSLog(@"open read db failed <%s>", strerror(errno));
    }
    
    // 初始化import线程
#if RUNLOOP_M1 == 1 || RUNLOOP_M2 == 1
    self.importValues = [NSMutableArray array];
    self.importThread = [[NSThread alloc] initWithTarget:self selector:@selector(_importThreadMain) object:nil];
    [self.importThread start];
    self.stopImportThread = NO;
#elif GCD_M == 1
    
#endif
}

#pragma mark private method

- (NSString *)_dbNameWithName:(NSString *)name
{
    NSString *dbName = [self.rootDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", name, DB_SUFFIX]];
    return dbName;
}

#pragma mark main method

- (LEFTSearchResult *)searchValueWithKeyword:(NSString *)keyword until:(NSTimeInterval)time
{
    return [self searchValueWithKeyword:keyword until:time orderBy:LEFTSearchOrderTypeNone];
}

- (LEFTSearchResult *)searchValueWithSentence:(NSString *)sentence until:(NSTimeInterval)time
{
    return nil;
}

- (LEFTSearchResult *)searchValueWithKeyword:(NSString *)keyword until:(NSTimeInterval)time orderBy:(LEFTSearchOrderType)type
{
    char *sql;
    NSMutableString *nsSql = [[NSMutableString alloc] init];
    [nsSql appendFormat:@"SELECT * FROM `%@` WHERE updatetime>=%.0lf", keyword, time];
    if (type != LEFTSearchOrderTypeNone) {
        [nsSql appendFormat:@" ORDER BY updatetime %@", type == LEFTSearchOrderTypeAsc ? @"ASC" : @"DESC"];
    }
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_stmt *stmt;
    sqlite3_prepare(_read_db, sql, (int)strlen(sql), &stmt, NULL);
    return [[LEFTSearchResult alloc] initWithStmt:stmt];
}

- (LEFTSearchResult *)searchValueWithSentence:(NSString *)sentence until:(NSTimeInterval)time orderBy:(LEFTSearchOrderType)type
{
    return nil;
}

- (BOOL)importValue:(LEFTValue *)value
{
#ifdef RUNLOOP_M1
    @synchronized (self.importValues) {
        [self.importValues addObject:value];
    }
#elif defined RUNLOOP_M2
    [self performSelector:@selector(_importValues:) onThread:self.importThread withObject:@[value] waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
#endif
    return YES;
}

- (BOOL)importValues:(NSArray *)values
{
#ifdef RUNLOOP_M1
    @synchronized (self.importValues) {
        [self.importValues addObjectsFromArray:values];
    }
#elif defined RUNLOOP_M2
    [self performSelector:@selector(_importValues:) onThread:self.importThread withObject:values waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#endif
    return YES;
}

- (BOOL)_importValues:(NSArray *)values
{
    for (LEFTValue *value in values) {
        NSLog(@"start import <=> %@", value);
        if ([value.keywords count] == 0) {
            value.keywords = [[self partcipleWrapper] minimumParticpleContent:value.content];
        }
        for (NSString *keyword in [value keywords]) {
            unsigned long long row = [self _checkValueExist:value keyword:keyword];
            if (row > 0) {
                [self _updateValue:value keyword:keyword];
            } else {
                [self _insertValue:value keyword:keyword];
            }
        }
    }
    return YES;
}

- (BOOL)deleteValuesWithKeyword:(NSString *)keyword
{
    return NO;
}

- (BOOL)truncate
{
    return NO;
}

- (void)startImporter:(id<LEFTDataImporter>)importer
{
    [self.dataImporters addObject:importer];
    importer.status = LEFTDataImporterStatusPending;
    
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        [importer start];
    }];
    operation.queuePriority = NSOperationQueuePriorityNormal;
    [self.importQueue addOperation:operation];
}

- (void)pauseImporter:(id<LEFTDataImporter>)importer
{
    if ([self.dataImporters containsObject:importer]) {
        [importer pause];
    }
}

- (void)resumeImporter:(id<LEFTDataImporter>)importer
{
    if ([self.dataImporters containsObject:importer]) {
        [importer start];
    }
}

- (BOOL)cancelImporter:(id<LEFTDataImporter>)importer
{
    if ([self.dataImporters containsObject:importer]) {
        return YES;
    }
    return NO;
}

- (NSArray *)importers
{
    return [NSArray arrayWithArray:self.dataImporters];
}

#pragma mark private method

- (unsigned long long)_checkValueExist:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *table_name;
    table_name = (char *)[keyword cStringUsingEncoding:NSUTF8StringEncoding];
    NSString *nsSql = [NSString stringWithFormat:CHECK_VALUE_ISEXIST, keyword, [value.identifier cStringUsingEncoding:NSUTF8StringEncoding], value.type];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_stmt *stmt;
    sqlite3_prepare(_write_db, sql, (int)strlen(sql), &stmt, NULL);
    
    unsigned long long row_id = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        row_id = sqlite3_column_int64(stmt, 0);
        if (row_id > 0) {
            break;
        }
    }
    sqlite3_finalize(stmt);
    return row_id;
}

- (void)_insertValue:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *err_str, *table_name;
    table_name = (char *)[keyword cStringUsingEncoding:NSUTF8StringEncoding];
    NSString *nsSql = [NSString stringWithFormat:CREATE_KEYWORD_TABLE_0_1, keyword];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    nsSql = [NSString stringWithFormat:INSERT_KEYWORD_QUERY, keyword,
             [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
             value.type,
             (long)value.updateTime,
             [value.content cStringUsingEncoding:NSUTF8StringEncoding],
             [[value userInfoString] cStringUsingEncoding:NSUTF8StringEncoding]];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
//    sqlite3_stmt *stmt;
//    sqlite3_prepare(_write_db, sql, (int)strlen(sql), &stmt, NULL);
    int changed = sqlite3_changes(_write_db);
    printf("%d changed", changed);
}

- (void)_updateValue:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *err_str, *table_name;
    table_name = (char *)[keyword cStringUsingEncoding:NSUTF8StringEncoding];
    NSString *nsSql = [NSString stringWithFormat:UPDATE_KEYWORD_QUERY, keyword,
                       [value.content cStringUsingEncoding:NSUTF8StringEncoding],
                       [value.userInfoString cStringUsingEncoding:NSUTF8StringEncoding],
                       [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                       value.type];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
//    sqlite3_stmt *stmt;
//    sqlite3_prepare(_write_db, sql, (int)strlen(sql), &stmt, NULL);
    int changed = sqlite3_changes(_write_db);
    printf("%d changed", changed);
}

- (void)_importThreadMain
{
    @try {
        while (!self.stopImportThread) {
#ifdef RUNLOOP_M1
            NSArray *tmpValues = nil;
            @synchronized (self.importValues) {
                if ([self.importValues count] > 0) {
                    tmpValues = [NSArray arrayWithArray:self.importValues];
                    [self.importValues removeAllObjects];
                }
            }
            [self _importValues:tmpValues];
#endif
            
            NSRunLoop *runloop = [NSRunLoop currentRunLoop];
            [runloop runUntilDate:[NSDate distantFuture]];
        }
    } @catch (NSException *exception) {
        NSLog(@"..... %@", exception);
    } @finally {
        
    }
}

@end


@implementation LEFTSearchResult
{
    sqlite3_stmt *_stmt;
    std::map<char *, int> _name_index;
}

- (void)dealloc
{
    sqlite3_finalize(_stmt);
}

- (instancetype)initWithStmt:(sqlite3_stmt *)stmt
{
    if (self = [super init]) {
        _stmt = stmt;
        if (_stmt != NULL) {
            int col_count = sqlite3_column_count(_stmt);
            for (int i = 0; i < col_count; i++) {
                char *name = (char *)sqlite3_column_name(_stmt, i);
                _name_index[name] = i;
            }
        }
    }
    return self;
}

- (LEFTValue *)next
{
    int res = sqlite3_step(_stmt);
    if (res == SQLITE_ROW) {
        LEFTValue *value = [[LEFTValue alloc] init];
        char *key_name;
        char *tmp_str_value;
        // idf
        key_name = (char *)"idf";
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index[key_name]);
        value.identifier = [NSString stringWithUTF8String:tmp_str_value];
        //"CREATE TABLE IF NOT EXISTS `%@` (idf TEXT NOT NULL, type INTEGER NOT NULL, updatetime INTEGER NOT NULL, content TEXT, userinfo TEXT);"
        // type
        key_name = (char *)"type";
        value.type = sqlite3_column_int(_stmt, _name_index[key_name]);
        // updatetime
        key_name = (char *)"updatetime";
        value.updateTime = sqlite3_column_int64(_stmt, _name_index[key_name]);
        // content
        key_name = (char *)"content";
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index[key_name]);
        value.content = [NSString stringWithUTF8String:tmp_str_value];
        // userinfo
        key_name = (char *)"userinfo";
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index[key_name]);
        id obj = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:tmp_str_value length:strlen(tmp_str_value)] options:0 error:nil];
        value.userInfo = obj;
        
        return value;
    }
    return nil;
}

@end
