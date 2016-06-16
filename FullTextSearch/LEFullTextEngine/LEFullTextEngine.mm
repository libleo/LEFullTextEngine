//
//  LEFullTextEngine.m
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFullTextEngine.h"
#import "LEFTValue.h"

#include "rocksdb/db.h"
#include "rocksdb/env.h"
#include "rocksdb/merge_operator.h"
#include "json.h"

#include <sqlite3.h>

#define KEYWORD_DB_SUFFIX @"db"
#define CURRENT_MAIN_DB_VER @"0.1"

// 目前没有加密功能

/*
 * 关键字 作为 tablename
 * table schema [identifier(str128), type(int), updatetime(timestamp), content(str512), userinfo(string)]
 *
 */

using namespace rocksdb;

typedef std::shared_ptr<rocksdb::DB>        TRocksDBPtr;
typedef std::shared_ptr<std::map<std::string, TRocksDBPtr>>  TMapRockDBPtr;

@interface LEFullTextEngine ()
{
    TRocksDBPtr m_db;
    TMapRockDBPtr m_db_map;
}

@property (nonatomic, copy) NSString *rootDirectory;

@property (nonatomic, strong) LEFTPartcipleWrapper *partcipleWrapper;
@property (nonatomic, strong) NSMutableArray *dataImporters;
@property (nonatomic, strong) NSOperationQueue *importQueue;

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
    
    std::string main_db_path = [[self.rootDirectory stringByAppendingPathComponent:@"main_db"] cStringUsingEncoding:NSUTF8StringEncoding];
    
    rocksdb::Options options;
    options.create_if_missing = true;
//    options.merge_operator.reset(new LEFTValueMergeOperator);
    rocksdb::DB* db = nullptr;
    rocksdb::Status status = rocksdb::DB::Open(options, main_db_path, &db);
    m_db.reset(db);
    
    m_db_map.reset(new std::map<std::string, TRocksDBPtr>);
    
    if (!status.ok()) {
        NSLog(@"create db fail code: <%d> subcode <%d>", status.code(), status.subcode());
    }
}

#pragma mark private method

- (NSString *)_keywordDBPathWithWord:(NSString *)word
{
    NSString *dbName = [self.rootDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", word, KEYWORD_DB_SUFFIX]];
    return dbName;
}

- (NSString *)_dbKeyWithValue:(LEFTValue *)value
{
    NSString *key = [NSString stringWithFormat:@"%d_%@", value.type, value.identifier];
    return key;
}

#pragma mark main method

- (NSArray *)searchValueWithKeyword:(NSString *)keyword
{
    rocksdb::Status s;
    std::string value;
    Slice k = [keyword cStringUsingEncoding:NSUTF8StringEncoding];
    s = m_db->Get(rocksdb::ReadOptions(), k, &value);

    if (!s.IsNotFound()) {
        // 转成LEFTValue
        NSString *valueString = [NSString stringWithCString:value.c_str() encoding:NSUTF8StringEncoding];
        NSError *error = nil;
        
        NSDictionary *dicData = [NSJSONSerialization JSONObjectWithData:[valueString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
        if (error) {
            NSLog(@"json parse error %@", [error localizedDescription]);
            return nil;
        }
        if (![dicData isKindOfClass:[NSDictionary class]]) {
            NSLog(@"json parse type error, data is %@", [dicData description]);
            return nil;
        }
        NSMutableArray *resultArray = [NSMutableArray array];
        NSString *path = dicData[@"path"];
        if (path != nil) {
            rocksdb::DB *keywordDB = NULL;
            rocksdb::Options options;
            s = rocksdb::DB::Open(options, [path cStringUsingEncoding:NSUTF8StringEncoding], &keywordDB);
            if (s.ok()) {
                rocksdb::Iterator *it = keywordDB->NewIterator(rocksdb::ReadOptions());
                for (it->SeekToFirst(); it->Valid(); it->Next()) {
                    std::string tmp = it->value().ToString();
                    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:tmp.c_str() length:tmp.length()] options:0 error:&error];
                    if (error == nil) {
                        LEFTValue *value = [[LEFTValue alloc] initWithDictionary:data];
                        [resultArray addObject:value];
                    }
                }
            } else {
                NSLog(@"status is %s", s.ToString().c_str());
            }
            delete keywordDB;
        }
        return resultArray;
    } else {
        NSLog(@"search db fail code: <%d> subcode <%d>", s.code(), s.subcode());
        NSLog(@"status is %s", s.ToString().c_str());
    }
    
    return nil;
}

- (NSArray *)searchValueWithSentence:(NSString *)sentence
{
    NSArray *keywords = [self.partcipleWrapper extractKeywordsWithContent:sentence];
    NSMutableArray *results = [NSMutableArray array];
    for (NSString *keyword in keywords) {
        NSArray *temp = [self searchValueWithKeyword:keyword];
        if ([temp count] > 0) {
            [results addObjectsFromArray:temp];
        }
    }
    return [NSArray arrayWithArray:results];
}

- (BOOL)importValue:(LEFTValue *)value
{
    NSData *json = [value JSONRepresentation];
    if ([value.keywords count] == 0) {
        value.keywords = [self.partcipleWrapper minimumParticpleContent:value.content];
    }
    BOOL flag = YES;
    for (NSString *key in value.keywords) {
        std::string key_string = [key cStringUsingEncoding:NSUTF8StringEncoding];
        TRocksDBPtr db = (*m_db_map)[key_string];
        if (db == nullptr) {
            NSString *dbName = [self _keywordDBPathWithWord:key];
            
            rocksdb::DB *indb;
            rocksdb::Options options;
            options.create_if_missing = true;
            rocksdb::Status s = rocksdb::DB::Open(options, [dbName cStringUsingEncoding:NSUTF8StringEncoding], &indb);
            
            if (s.ok()) {
                db.reset(indb);
                Slice k = [[self _dbKeyWithValue:value] cStringUsingEncoding:NSUTF8StringEncoding];
                Slice *v = new Slice((const char*)json.bytes, json.length);
                s = db->Put(rocksdb::WriteOptions(), k, *v);
                if (s.ok()) {
                    flag &= YES;
                } else {
                    NSLog(@"import value fail code: <%d> subcode <%d>", s.code(), s.subcode());
                    flag &= NO;
                }
                delete v;
            }
        }
    }
    return flag;
}

- (BOOL)importValues:(NSArray *)values
{
    clock_t start = clock();
    std::map<std::string, rocksdb::DB *> db_map;
    std::map<std::string, rocksdb::WriteBatch *> batch_map;
    rocksdb::WriteBatch batch;
    for (LEFTValue *value in values) {
        NSData *json = [value JSONRepresentation];
        if ([value.keywords count] == 0) {
            value.keywords = [self.partcipleWrapper minimumParticpleContent:value.content];
        }
        for (NSString *key in value.keywords) {
            NSString *dbName = [self _keywordDBPathWithWord:key];
            std::string key_string = [key cStringUsingEncoding:NSUTF8StringEncoding];
            rocksdb::WriteBatch *batch = batch_map[key_string];
            TRocksDBPtr db = (*m_db_map)[key_string];
            if (db == nullptr) {
                rocksdb::DB *indb;
                rocksdb::Options options;
                options.create_if_missing = true;
                rocksdb::Status s = rocksdb::DB::Open(options, [dbName cStringUsingEncoding:NSUTF8StringEncoding], &indb);
                
                if (s.ok()) {
                    
                    Slice main_key = key_string;
                    NSDictionary *mainDic = @{@"ver": CURRENT_MAIN_DB_VER,
                                              @"path": dbName};
                    NSData *data = [NSJSONSerialization dataWithJSONObject:mainDic options:0 error:nil];
                    Slice *main_value = new Slice((const char *)[data bytes], [data length]);
                    m_db->Put(rocksdb::WriteOptions(), main_key, *main_value);
                    
                    db.reset(indb);
                    delete main_value;
                }
            }
            if (batch == NULL) {
                batch = new rocksdb::WriteBatch();
                batch_map[key_string] = batch;
            }
            Slice k = [[self _dbKeyWithValue:value] cStringUsingEncoding:NSUTF8StringEncoding];
            Slice *v = new Slice((const char*)json.bytes, json.length);
            batch->Put(k, *v);
        }
    }
    BOOL flag = YES;
    for (auto iter : *m_db_map) {
        rocksdb::WriteBatch *batch = batch_map[iter.first];
        if (batch != NULL && iter.second != NULL) {
            rocksdb::Status s = iter.second->Write(rocksdb::WriteOptions(), batch);
            if (!s.ok()) {
                NSLog(@"import value fail code: <%d> subcode <%d>", s.code(), s.subcode());
                flag &= NO;
            }
            iter.second->Flush(rocksdb::FlushOptions());
            delete batch;
        }
    }
    
    NSLog(@"use time <%lf> import value", double(clock()-start)/CLOCKS_PER_SEC);
    return flag;
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


@end
