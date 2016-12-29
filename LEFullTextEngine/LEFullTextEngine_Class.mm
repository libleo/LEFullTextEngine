//
//  LEFullTextEngine.m
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFullTextEngine_Class.h"
#import "LEFTPartcipleWrapper.h"
#import "LEFTDataImporter.h"
#import "LEFTValue.h"

#include "json.h"
#include <sqlite3.h>

static NSString *sErrorDomain = @"LEFT SQLite Error";

#define DB_SUFFIX @"idxdb"
#define CURRENT_MAIN_DB_VER @"0.2"

#define CREATE_KEYWORD_TABLE_0_2 @"CREATE TABLE IF NOT EXISTS `%@` (idf VARCHAR(128) NOT NULL, type INTEGER NOT NULL, updatetime INTEGER NOT NULL, tag VARCHAR, PRIMARY KEY (idf, type));"
#define CREATE_CONTENT_TABLE_0_2 @"CREATE TABLE IF NOT EXISTS `_content_cache` (idf VARCHAR(128) NOT NULL, type INTEGER NOT NULL, content TEXT, userinfo TEXT);"
#define DELETE_TABLE @"DELETE FROM `%@`"

// 模式切换
#define RUNLOOP_M
//#define GCD_M 1

// 目前没有加密功能

extern "C" {
    static void DoNothingRunLoopCallback(void *info)
    {
        
    }
    
    static NSError *GenNSErrorWithDBHandler(sqlite3 *db)
    {
        const char *errormsg = sqlite3_errmsg(db);
        int errorcode = sqlite3_errcode(db);
        NSError *error;
        NSString *errorString = [NSString stringWithUTF8String:errormsg];
        if (errorString != nil) {
            error = [NSError errorWithDomain:sErrorDomain code:errorcode userInfo:@{NSLocalizedDescriptionKey: errorString}];
        } else {
            NSLog(@"error string gen fail...%s", errormsg);
        }
        return error;
    }
}

@interface LEFTSearchResult ()

- (instancetype)initWithStmt:(sqlite3_stmt *)stmt;
- (instancetype)initWithError:(NSError *)error;

@end

/*
 * 关键字 作为 tablename
 * table schema [identifier(str128), type(int), updatetime(timestamp), content(str512), userinfo(string)]
 *
 */

@interface LEFullTextEngine ()
{
    sqlite3 *_write_db;
    sqlite3 *_read_db;
    sqlite3 *_main_thread_db;
#if GCD_M == 1
    dispatch_queue_t _import_queue;
#endif
}

@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic, copy) NSString *dbPath;
@property (nonatomic, strong) LEFTPartcipleWrapper *partcipleWrapper;
@property (nonatomic, strong) NSMutableArray *dataImporters;
@property (nonatomic, strong) NSOperationQueue *importQueue;
@property (nonatomic, strong) NSThread *fetchThread;
@property (assign) BOOL stopFetchThread;

#ifdef RUNLOOP_M
@property (nonatomic, strong) NSThread *importThread;
@property (assign) BOOL stopImportThread;
#endif

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
    
    self.partcipleWrapper = [LEFTPartcipleWrapper shareInstance];
    self.dataImporters = [NSMutableArray array];
    self.importQueue = [[NSOperationQueue alloc] init];
    
    self.importerPriority = NSOperationQueuePriorityNormal;
    self.importQueue.maxConcurrentOperationCount = 3;
    [self.importQueue setSuspended:NO];
    
    self.indexMode = LEFTIndexModePure;
    
    int safe = sqlite3_threadsafe();
    NSLog(@"thread safe %d", safe);
    self.dbPath = [self _dbNameWithName:@"main"];
    const char *db_path = [self.dbPath cStringUsingEncoding:NSUTF8StringEncoding];
    res = sqlite3_open(db_path, &_write_db);
    if (res != 0) {
        NSLog(@"open write db failed <%s>", strerror(errno));
    }
    res = sqlite3_open(db_path, &_read_db);
    if (res != 0) {
        NSLog(@"open read db failed <%s>", strerror(errno));
    }
    res = sqlite3_open(db_path, &_main_thread_db);
    if (res != 0) {
        NSLog(@"open main_thread db failed <%s>", strerror(errno));
    }
    
    // 初始化fetch线程
    self.fetchThread = [[NSThread alloc] initWithTarget:self selector:@selector(_fetchThreadMain) object:nil];
    [self.fetchThread start];
    // 初始化import线程
#ifdef RUNLOOP_M
    self.importThread = [[NSThread alloc] initWithTarget:self selector:@selector(_importThreadMain) object:nil];
    [self.importThread start];
    self.stopImportThread = NO;
#elif GCD_M == 1
    _import_queue = dispatch_queue_create("import_queue", NULL);
#endif
}

#pragma mark private method

- (NSString *)_dbNameWithName:(NSString *)name
{
    NSString *dbName = [self.rootDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", name, DB_SUFFIX]];
    return dbName;
}

#pragma mark main method

- (BOOL)hasKeyword:(NSString *)keyword
{
    char *sql;
    NSString *nsSql = [NSString stringWithFormat:@"SELECT `rowid` FROM `sqlite_master` WHERE name=\"%@\"", keyword];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(_main_thread_db, sql, (int)strlen(sql), &stmt, NULL);
    
    unsigned long long row_id = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        row_id = sqlite3_column_int64(stmt, 0);
        if (row_id > 0) {
            break;
        }
    }
    sqlite3_finalize(stmt);
    return row_id > 0;
}

- (void)searchValueWithKeywords:(NSArray *)keywords until:(NSTimeInterval)time resultHandler:(LEFTResultHandler)handler
{
    [self searchValueWithKeywords:keywords until:time customType:NSUIntegerMax tag:nil orderBy:LEFTSearchOrderTypeNone resultHandler:handler];
}

- (void)searchValueWithSentence:(NSString *)sentence until:(NSTimeInterval)time resultHandler:(LEFTResultHandler)handler
{
    NSArray *keywords = [[self partcipleWrapper] minimumParticipleContent:sentence];
    if ([keywords count] > 0) {
        [self searchValueWithKeywords:keywords until:time customType:NSUIntegerMax tag:nil orderBy:LEFTSearchOrderTypeNone resultHandler:handler];
    } else {
        handler(nil);
    }
}

- (void)searchValueWithSentence:(NSString *)sentence customType:(NSUInteger)customType until:(NSTimeInterval)time tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType resultHandler:(LEFTResultHandler)handler
{
    NSArray *keywords = [[self partcipleWrapper] minimumParticipleContent:sentence];
    if ([keywords count] > 0) {
        [self searchValueWithKeywords:keywords until:time customType:customType tag:tag orderBy:orderType resultHandler:handler];
    } else {
        handler(nil);
    }
}

- (void)searchValueWithKeywords:(NSArray *)keywords until:(NSTimeInterval)time customType:(NSUInteger)customType tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType resultHandler:(LEFTResultHandler)handler
{
    NSArray *filterKeywords = [self _filterKeywords:keywords];
    LEFTIndexMode indexMode = self.indexMode;
    NSMutableString *nsSql = [[NSMutableString alloc] init];
    [filterKeywords enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx > 0) {
            [nsSql appendString:@" INTERSECT "];
        }
        [nsSql appendFormat:@"SELECT * FROM `%@` WHERE updatetime>=%.0lf", keyword, time];
        if (indexMode == LEFTIndexModeCacheContent) {
            [nsSql appendFormat:@" JOIN `_content_cache` ON `%@`.idf = `_content_cache`.idf AND `%@`.type = `_content_cache`.type ", keyword, keyword];
        }
        if (customType != NSUIntegerMax) {
            [nsSql appendFormat:@" AND type=%zd ", customType];
        }
        if (tag != nil) {
            [nsSql appendFormat:@" AND tag=%@ ", tag];
        }
        if (orderType != LEFTSearchOrderTypeNone) {
            [nsSql appendFormat:@" ORDER BY updatetime %@", orderType == LEFTSearchOrderTypeAsc ? @"ASC" : @"DESC"];
        }
    }];
    NSDictionary *extraParams = @{@"sql" : nsSql,
                                  @"handler" : handler};
    [self performSelector:@selector(_performFetchSQL:) onThread:self.fetchThread withObject:extraParams waitUntilDone:NO];
}

- (LEFTSearchResult *)searchValueSyncWithSentence:(NSString *)sentence until:(NSTimeInterval)time customType:(NSUInteger)customType tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType;
{
    NSArray *keywords = [[self partcipleWrapper] minimumParticipleContent:sentence];
    return [self searchValueSyncWithKeywords:keywords until:time customType:customType tag:tag orderBy:orderType];
}

- (LEFTSearchResult *)searchValueSyncWithKeywords:(NSArray *)keywords until:(NSTimeInterval)time customType:(NSUInteger)customType tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType
{
    NSArray *filterKeywords = [self _filterKeywords:keywords];
    LEFTIndexMode indexMode = self.indexMode;
    NSMutableString *nsSql = [[NSMutableString alloc] init];
    [filterKeywords enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx > 0) {
            [nsSql appendString:@" INTERSECT "];
        }
        [nsSql appendFormat:@"SELECT * FROM `%@` WHERE updatetime>=%.0lf", keyword, time];
        if (indexMode == LEFTIndexModeCacheContent) {
            [nsSql appendFormat:@" JOIN `_content_cache` ON `%@`.idf = `_content_cache`.idf AND `%@`.type = `_content_cache`.type ", keyword, keyword];
        }
        if (customType != NSUIntegerMax) {
            [nsSql appendFormat:@" AND type=%zd ", customType];
        }
        if (tag != nil) {
            [nsSql appendFormat:@" AND tag=%@ ", tag];
        }
        if (orderType != LEFTSearchOrderTypeNone) {
            [nsSql appendFormat:@" ORDER BY updatetime %@", orderType == LEFTSearchOrderTypeAsc ? @"ASC" : @"DESC"];
        }
    }];
    
    char *sql;
    clock_t start = clock();
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(_main_thread_db, sql, (int)strlen(sql), &stmt, NULL);
    LEFTSearchResult *result = [[LEFTSearchResult alloc] initWithStmt:stmt];
    result.usedClock = clock() - start;
    
    return result;
}

- (void)_performFetchSQL:(NSDictionary *)params
{
    @autoreleasepool {
        NSString *fetchSQL = [[params objectForKey:@"sql"] copy];
        LEFTResultHandler handler = [params objectForKey:@"handler"];
        char *sql;
        sql = (char *)[fetchSQL cStringUsingEncoding:NSUTF8StringEncoding];
        sqlite3_stmt *stmt;
        NSError *error;
        LEFTSearchResult *result;
        int res = sqlite3_prepare_v2(_read_db, sql, (int)strlen(sql), &stmt, NULL);
        if (res != SQLITE_OK) {
            error = GenNSErrorWithDBHandler(_read_db);
            result = [[LEFTSearchResult alloc] initWithError:error];
        } else {
            result = [[LEFTSearchResult alloc] initWithStmt:stmt];
        }
        
        if (handler) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                handler(result);
            });
        }
    }
}

- (BOOL)importValue:(LEFTValue *)value
{
#ifdef RUNLOOP_M
    [self performSelector:@selector(_importValues:) onThread:self.importThread withObject:@[value] waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
    __weak typeof(self) weakSelf = self;
    dispatch_async(_import_queue, ^{
        [weakSelf _importValues:@[value]];
    });
#endif
    return YES;
}

- (BOOL)importValues:(NSArray *)values
{
#ifdef RUNLOOP_M
    [self performSelector:@selector(_importValues:) onThread:self.importThread withObject:values waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
    __weak typeof(self) weakSelf = self;
    dispatch_async(_import_queue, ^{
        [weakSelf _importValues:values];
    });
#endif
    return YES;
}

- (BOOL)importValuesSync:(NSArray *)values
{
#ifdef RUNLOOP_M
    [self performSelector:@selector(_importValues:) onThread:self.importThread withObject:values waitUntilDone:YES modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
    __weak typeof(self) weakSelf = self;
    dispatch_sync(_import_queue, ^{
        [weakSelf _importValues:values];
    });
#endif
    return YES;
}

- (BOOL)_importValues:(NSArray *)values
{
    @autoreleasepool {
        char *err_str = NULL;
        int res = sqlite3_exec(_write_db, "BEGIN;", 0, 0, &err_str);
        //执行SQL语句
        if (res == SQLITE_OK) {
            for (LEFTValue *value in values) {
                if ([value.keywords count] == 0) {
                    value.keywords = [[self partcipleWrapper] minimumParticipleContent:value.content];
                }
                for (NSString *keyword in [value keywords]) {
                    [self _insertOrReplaceValue:value keyword:keyword];
                }
                if (self.indexMode == LEFTIndexModeCacheContent) {
                    [self _importValueContent:value];
                }
            }
            res &= sqlite3_exec(_write_db, "COMMIT;", 0, 0, &err_str);
            if (res != SQLITE_OK) {
                printf("fail commit error <%s>\n", err_str);
            }
        } else {
            printf("sql begin error <%s>\n", err_str);
        }
        sqlite3_free(err_str);
        return YES;
    }
}

- (BOOL)_importValueContent:(LEFTValue *)value
{
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:CREATE_CONTENT_TABLE_0_2];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    
    sql = sqlite3_mprintf("REPLACE INTO `_content_cache` (idf, type, content, userinfo) VALUES (\"%q\", %d, \"%q\", '%q')",
                          [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                          value.type,
                          value.content,
                          [value.userInfoString cStringUsingEncoding:NSUTF8StringEncoding]);
    int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    int changed = sqlite3_changes(_write_db);
    if (changed == 0) {
        printf("insert content cache failed <%d>\n", res);
        printf("sql is <%s>\n", sql);
        printf("error str <%s>", err_str);
    }
    sqlite3_free(err_str);
    sqlite3_free(sql);
    return res == SQLITE_OK;
}

- (BOOL)deleteDataBeforeDate:(NSDate *)date
{
    @autoreleasepool {
#ifdef RUNLOOP_M
        [self performSelector:@selector(_deleteBeforeDate:) onThread:self.importThread withObject:date waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
        __weak typeof(self) weakSelf = self;
        dispatch_async(_import_queue, ^{
            [weakSelf _deleteTable:keyword];
        });
#endif
    }
    return YES;
}

- (BOOL)deleteValuesWithKeyword:(NSString *)keyword
{
    @autoreleasepool {
#ifdef RUNLOOP_M
        [self performSelector:@selector(_deleteTable:) onThread:self.importThread withObject:keyword waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
        __weak typeof(self) weakSelf = self;
        dispatch_async(_import_queue, ^{
            [weakSelf _deleteTable:keyword];
        });
#endif
    }
    return YES;
}

- (BOOL)deleteWithValue:(LEFTValue *)value
{
    @autoreleasepool {
#ifdef RUNLOOP_M
        [self performSelector:@selector(_deleteValue:) onThread:self.importThread withObject:value waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
#elif defined GCD_M
        __weak typeof(self) weakSelf = self;
        dispatch_async(_import_queue, ^{
            [weakSelf _deleteValue:value];
        });
#endif
    }
    return YES;
}

- (BOOL)truncate
{
    const char *db_path = [self.dbPath cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_close(_write_db);
    sqlite3_close(_read_db);
    sqlite3_close(_main_thread_db);
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:&error];
    if (error) {
        NSLog(@"truncate db error ... <%@>", [error localizedDescription]);
    }
    int res = sqlite3_open(db_path, &_write_db);
    if (res != 0) {
        NSLog(@"open write db failed <%s>", strerror(errno));
        return NO;
    }
    res = sqlite3_open(db_path, &_read_db);
    if (res != 0) {
        NSLog(@"open read db failed <%s>", strerror(errno));
        return NO;
    }
    res = sqlite3_open(db_path, &_main_thread_db);
    if (res != 0) {
        NSLog(@"open main_thread db failed <%s>", strerror(errno));
        return NO;
    }
    return YES;
}

- (void)setConcurrentImporterCount:(NSUInteger)count
{
    self.importQueue.maxConcurrentOperationCount = count;
}

- (NSUInteger)concurrentImporterCount
{
    return self.importQueue.maxConcurrentOperationCount;
}

- (void)startImporter:(id<LEFTDataImporter>)importer
{
    [self.dataImporters addObject:importer];
    importer.status = LEFTDataImporterStatusPending;
    
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        [importer start];
    }];
    operation.queuePriority = self.importerPriority;
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

// 准备语句和数据库
- (sqlite3_stmt *)_executeSQL:(NSString *)nsSql withHandler:(sqlite3 *)handler
{
    sqlite3_stmt *stmt;
    char *sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_prepare_v2(handler, sql, (int)strlen(sql), &stmt, NULL);
    
    return stmt;
}

- (BOOL)_checkTableHasRow:(NSString *)tableName withHandler:(sqlite3 *)handler
{
    NSString *nsSql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM `%@`", tableName];
    sqlite3_stmt *stmt = [self _executeSQL:nsSql withHandler:handler];
    
    unsigned long long count = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
        if (count > 0) {
            break;
        }
    }
    sqlite3_finalize(stmt);
    return count > 0;
}

- (NSArray *)_filterKeywords:(NSArray *)keywords
{
    NSMutableArray *filterKeywords = [NSMutableArray arrayWithCapacity:[keywords count]];
    for (NSString *keyword in keywords) {
        if ([self hasKeyword:keyword]) {
            [filterKeywords addObject:keyword];
        }
    }
    return [NSArray arrayWithArray:filterKeywords];
}

- (unsigned long long)_checkValueExist:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql;
    NSString *nsSql = [NSString stringWithFormat:@"SELECT `rowid`, `idf`, `type` FROM `%@` WHERE idf=\"%s\" AND type=%d LIMIT 1", keyword, [value.identifier cStringUsingEncoding:NSUTF8StringEncoding], value.type];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_stmt *stmt = [self _executeSQL:nsSql withHandler:_write_db];
    
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

- (void)_insertOrReplaceValue:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:CREATE_KEYWORD_TABLE_0_2, keyword];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    
    sql = sqlite3_mprintf("REPLACE INTO `%s` (idf, type, updatetime, tag) VALUES (\"%q\", %d, %ld, \"%q\")",
                          [keyword cStringUsingEncoding:NSUTF8StringEncoding],
                          [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                          value.type,
                          (long)value.updateTime,
                          value.tag ? [value.tag cStringUsingEncoding:NSUTF8StringEncoding] : "null");
    int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    int changed = sqlite3_changes(_write_db);
    if (changed == 0) {
        printf("insert changed failed <%d>\n", res);
        printf("sql is <%s>\n", sql);
        printf("error str <%s>", err_str);
    }
    sqlite3_free(err_str);
    sqlite3_free(sql);
}

- (void)_insertValue:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:CREATE_KEYWORD_TABLE_0_2, keyword];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);

    sql = sqlite3_mprintf("INSERT INTO `%s` (idf, type, updatetime, tag) VALUES (\"%q\", %d, %ld, \"%q\", '%q', \"%q\")",
                          [keyword cStringUsingEncoding:NSUTF8StringEncoding],
                          [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                          value.type,
                          (long)value.updateTime,
                          value.tag ? [value.tag cStringUsingEncoding:NSUTF8StringEncoding] : "null");
    int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    int changed = sqlite3_changes(_write_db);
    if (changed == 0) {
        printf("insert changed failed <%d>\n", res);
        printf("sql is <%s>\n", sql);
        printf("error str <%s>", err_str);
    }
    sqlite3_free(err_str);
    sqlite3_free(sql);
}

- (void)_updateValue:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *err_str;
    sql = sqlite3_mprintf("UPDATE `%s` SET tag=\"%q\" WHERE idf=\"%q\" AND type=%d",
                          [keyword cStringUsingEncoding:NSUTF8StringEncoding],
                          value.tag ? [value.tag cStringUsingEncoding:NSUTF8StringEncoding] : "null",
                          [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                          value.type);

    int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    int changed = sqlite3_changes(_write_db);
    if (changed == 0) {
        printf("update changed failed <%d>", res);
        printf("sql is <%s>\n", sql);
        printf("error str <%s>", err_str);
    }
    sqlite3_free(err_str);
    sqlite3_free(sql);
}

- (void)_deleteBeforeDate:(NSDate *)date
{
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:@"SELECT `tbl_name` FROM `sqlite_master` WHERE type=\"table\""];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(_write_db, sql, (int)strlen(sql), &stmt, NULL);
    
    unsigned char *table_name = 0;
    NSMutableArray *tableNames = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        table_name = (unsigned char *)sqlite3_column_text(stmt, 0);
        if (table_name != NULL) {
            NSString *tableName = [NSString stringWithCString:(const char *)table_name encoding:NSUTF8StringEncoding];
            [tableNames addObject:tableName];
        }
    }
    sqlite3_finalize(stmt);

    NSTimeInterval timeInterval = [date timeIntervalSince1970];
    for (NSString *tableName in tableNames) {
        NSString *nsSql = [NSString stringWithFormat:@"DELETE FROM `%@` WHERE updatetime <= %.0lf", tableName, timeInterval];
        sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
        int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
        if (res != SQLITE_OK) {
            printf("delete table %s error <%s>", [tableName cStringUsingEncoding:NSUTF8StringEncoding], err_str);
        }
        sqlite3_free(err_str);
        if (![self _checkTableHasRow:tableName withHandler:_write_db]) {
            [self _deleteTable:tableName];
        }
    }
}

- (void)_deleteTable:(NSString *)tableName
{
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:@"DROP TABLE `%@`", tableName];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    if (res != SQLITE_OK) {
        printf("drop table %s error <%s>", [tableName cStringUsingEncoding:NSUTF8StringEncoding], err_str);
    }
    sqlite3_free(err_str);
}

- (void)_deleteValue:(LEFTValue *)value
{
    char *sql, *err_str;
    int res = sqlite3_exec(_write_db, "BEGIN;", 0, 0, &err_str);
    for (NSString *keyword in [value keywords]) {
        const char *key = [keyword cStringUsingEncoding:NSUTF8StringEncoding];
        sql = sqlite3_mprintf("DELETE FROM `%s` WHERE idf=\"%q\" AND type=%d",
                              key,
                              [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                              value.type);
        res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
        int changed = sqlite3_changes(_write_db);
        if (changed == 0) {
            printf("delete from %s failed <%d>\n", key, res);
            printf("sql is <%s>\n", sql);
            printf("error str <%s>\n", err_str);
        }
        sqlite3_free(err_str);
        sqlite3_free(sql);
    }
    res &= sqlite3_exec(_write_db, "COMMIT;", 0, 0, &err_str);
}

- (void)_fetchThreadMain
{
    @autoreleasepool {
        CFRunLoopSourceContext context = {0};
        context.perform = DoNothingRunLoopCallback;
        
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        
        // Keep processing events until the runloop is stopped.
        CFRunLoopRun();
        
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        CFRelease(source);
    }
}

#ifdef RUNLOOP_M
- (void)_importThreadMain
{
    @autoreleasepool {
        CFRunLoopSourceContext context = {0};
        context.perform = DoNothingRunLoopCallback;
        
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        
        // Keep processing events until the runloop is stopped.
        CFRunLoopRun();
        
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        CFRelease(source);
    }
}
#endif

@end


#pragma mark - LEFTSearchResult

@implementation LEFTSearchResult
{
    sqlite3_stmt *_stmt;
    std::map<std::string, int> _name_index;
}

@synthesize error = _error;

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

- (instancetype)initWithError:(NSError *)error
{
    if (self = [super init]) {
        _error = error;
    }
    return self;
}

- (BOOL)succeed
{
    if (self.error == nil && _stmt != NULL) {
        return YES;
    }
    return NO;
}

- (LEFTValue *)next
{
    int res = sqlite3_step(_stmt);
    if (res == SQLITE_ROW) {
        LEFTValue *value = [[LEFTValue alloc] init];
        char *tmp_str_value;
        // idf
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["idf"]);
        value.identifier = [NSString stringWithUTF8String:tmp_str_value];
        //"CREATE TABLE IF NOT EXISTS `%@` (idf TEXT NOT NULL, type INTEGER NOT NULL, updatetime INTEGER NOT NULL, content TEXT, userinfo TEXT);"
        // type
        value.type = sqlite3_column_int(_stmt, _name_index["type"]);
        // updatetime
        value.updateTime = sqlite3_column_int64(_stmt, _name_index["updatetime"]);
//        // content
//        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["content"]);
//        value.content = [NSString stringWithUTF8String:tmp_str_value];
//        // userinfo
//        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["userinfo"]);
//        id obj = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:tmp_str_value length:strlen(tmp_str_value)] options:0 error:nil];
//        value.userInfo = obj;
        // tag
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["tag"]);
        value.tag = [NSString stringWithUTF8String:tmp_str_value];
        
        return value;
    } else if (res == SQLITE_DONE) {
        return nil;
    } else {
        
    }
    return nil;
}

@end
