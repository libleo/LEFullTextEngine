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

#define DB_SUFFIX @"idxdb"
#define CURRENT_MAIN_DB_VER @"0.1"

#define CREATE_KEYWORD_TABLE_0_1 @"CREATE TABLE IF NOT EXISTS `%@` (idf TEXT NOT NULL, type INTEGER NOT NULL, updatetime INTEGER NOT NULL, content TEXT, userinfo TEXT, tag VARCHAR);"
#define CHECK_VALUE_ISEXIST @"SELECT `rowid`, `idf`, `type` FROM `%@` WHERE idf=\"%s\" AND type=%d;"
#define DELETE_TABLE @"DELETE FROM `%@`"

// 模式切换
#define RUNLOOP_M
//#define GCD_M 1

// 目前没有加密功能

extern "C" {
    static void DoNothingRunLoopCallback(void *info)
    {
        
    }
}

@interface LEFTSearchResult ()

- (instancetype)initWithStmt:(sqlite3_stmt *)stmt;

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
    
    self.importQueue.maxConcurrentOperationCount = 3;
    [self.importQueue setSuspended:NO];
    
    int safe = sqlite3_threadsafe();
    NSLog(@"thread safe %d", safe);
    const char *db_path = [[self _dbNameWithName:@"main"] cStringUsingEncoding:NSUTF8StringEncoding];
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
    sqlite3_prepare(_main_thread_db, sql, (int)strlen(sql), &stmt, NULL);
    
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
    NSArray *keywords = [[self partcipleWrapper] minimumParticpleContent:sentence];
    if ([keywords count] > 0) {
        [self searchValueWithKeywords:keywords until:time customType:NSUIntegerMax tag:nil orderBy:LEFTSearchOrderTypeNone resultHandler:handler];
    } else {
        handler(nil);
    }
}

- (void)searchValueWithSentence:(NSString *)sentence customType:(NSUInteger)customType until:(NSTimeInterval)time tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType resultHandler:(LEFTResultHandler)handler
{
    NSArray *keywords = [[self partcipleWrapper] minimumParticpleContent:sentence];
    if ([keywords count] > 0) {
        [self searchValueWithKeywords:keywords until:time customType:customType tag:tag orderBy:orderType resultHandler:handler];
    } else {
        handler(nil);
    }
}

- (void)searchValueWithKeywords:(NSArray *)keywords until:(NSTimeInterval)time customType:(NSUInteger)customType tag:(NSString *)tag orderBy:(LEFTSearchOrderType)orderType resultHandler:(LEFTResultHandler)handler
{
    NSArray *filterKeywords = [self _filterKeywords:keywords];
    NSMutableString *nsSql = [[NSMutableString alloc] init];
    [filterKeywords enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx > 0) {
            [nsSql appendString:@" INTERSECT "];
        }
        [nsSql appendFormat:@"SELECT * FROM `%@` WHERE updatetime>=%.0lf", keyword, time];
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

- (void)_performFetchSQL:(NSDictionary *)params
{
    @autoreleasepool {
        NSString *fetchSQL = [[params objectForKey:@"sql"] copy];
        LEFTResultHandler handler = [params objectForKey:@"handler"];
        char *sql;
        sql = (char *)[fetchSQL cStringUsingEncoding:NSUTF8StringEncoding];
        sqlite3_stmt *stmt;
        sqlite3_prepare(_read_db, sql, (int)strlen(sql), &stmt, NULL);
        LEFTSearchResult *result = [[LEFTSearchResult alloc] initWithStmt:stmt];
        
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
            res = sqlite3_exec(_write_db, "COMMIT;", 0, 0, &err_str);
            if (res != SQLITE_OK) {
                printf("fail commit error <%s>\n", err_str);
            }
        } else {
            printf("sql begin error <%s>\n", err_str);
        }
        return YES;
    }
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
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:CREATE_KEYWORD_TABLE_0_1, keyword];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);

    sql = sqlite3_mprintf("INSERT INTO `%s` (idf, type, updatetime, content, userinfo, tag) VALUES (\"%q\", %d, %ld, \"%q\", '%q', \"%q\")",
                          [keyword cStringUsingEncoding:NSUTF8StringEncoding],
                          [value.identifier cStringUsingEncoding:NSUTF8StringEncoding],
                          value.type,
                          (long)value.updateTime,
                          [value.content cStringUsingEncoding:NSUTF8StringEncoding],
                          [value.userInfoString cStringUsingEncoding:NSUTF8StringEncoding],
                          value.tag ? [value.tag cStringUsingEncoding:NSUTF8StringEncoding] : "null");
    int res = sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
    int changed = sqlite3_changes(_write_db);
    if (changed == 0) {
        printf("insert changed failed <%d>\n", res);
        printf("sql is <%s>\n", sql);
        printf("error str <%s>", err_str);
    }
    sqlite3_free(sql);
}

- (void)_updateValue:(LEFTValue *)value keyword:(NSString *)keyword
{
    char *sql, *err_str;
    sql = sqlite3_mprintf("UPDATE `%s` SET content=\"%q\", userinfo='%q', tag=\"%q\" WHERE idf=\"%q\" AND type=%d",
                          [keyword cStringUsingEncoding:NSUTF8StringEncoding],
                          [value.content cStringUsingEncoding:NSUTF8StringEncoding],
                          [value.userInfoString cStringUsingEncoding:NSUTF8StringEncoding],
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
    sqlite3_free(sql);
}

- (void)_deleteTable:(NSString *)tableName
{
    char *sql, *err_str;
    NSString *nsSql = [NSString stringWithFormat:DELETE_TABLE, tableName];
    sql = (char *)[nsSql cStringUsingEncoding:NSUTF8StringEncoding];
    sqlite3_exec(_write_db, sql, NULL, NULL, &err_str);
//    int changed = sqlite3_changes(_write_db);
//    printf("%d changed\n", changed);
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
        char *tmp_str_value;
        // idf
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["idf"]);
        value.identifier = [NSString stringWithUTF8String:tmp_str_value];
        //"CREATE TABLE IF NOT EXISTS `%@` (idf TEXT NOT NULL, type INTEGER NOT NULL, updatetime INTEGER NOT NULL, content TEXT, userinfo TEXT);"
        // type
        value.type = sqlite3_column_int(_stmt, _name_index["type"]);
        // updatetime
        value.updateTime = sqlite3_column_int64(_stmt, _name_index["updatetime"]);
        // content
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["content"]);
        value.content = [NSString stringWithUTF8String:tmp_str_value];
        // userinfo
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["userinfo"]);
        id obj = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:tmp_str_value length:strlen(tmp_str_value)] options:0 error:nil];
        value.userInfo = obj;
        // tag
        tmp_str_value = (char *)sqlite3_column_text(_stmt, _name_index["tag"]);
        value.tag = [NSString stringWithUTF8String:tmp_str_value];
        
        return value;
    }
    return nil;
}

@end
