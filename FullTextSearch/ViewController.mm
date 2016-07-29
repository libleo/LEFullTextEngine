//
//  ViewController.m
//  FullTextSearch
//
//  Created by Leo on 16/5/20.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "ViewController.h"
#import "LEFTSQLDataImporter.h"


@interface ViewController ()

@property (nonatomic, strong) LEFullTextEngine *fulltextEngine;

@end

@implementation ViewController

+ (void)load
{
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    clock_t begin = clock();
    self.fulltextEngine = [[LEFullTextEngine alloc] init];
    NSLog(@"init time use %lf", double(clock() - begin)/CLOCKS_PER_SEC);
    
    LEFTSQLDataImporter *importor = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    __weak typeof(importor) weakImport = importor;
    importor.dbPath = @"/Users/Leo/Documents/imchatdb/immsghis.db";
    importor.importProcess = ^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:@"SELECT * FROM instantmsg"];
        //            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
        while ([set next]) {
            LEFTValue *value = [[LEFTValue alloc] init];
            value.identifier = [NSString stringWithFormat:@"msg_%ld", [set longForColumn:@"guuid"]];
            value.type = 1;
            value.updateTime = [set longForColumn:@"dtime"];
            value.content = [set stringForColumn:@"content"];
            
            [weakImport.engine importValue:value];
//            NSLog(@"msg import value <%@>", value);
        }
    };
    
    LEFTSQLDataImporter *sysImportor = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    weakImport = sysImportor;
    sysImportor.dbPath = @"/Users/Leo/Documents/imchatdb/sysmsghis.db";
    sysImportor.importProcess = ^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:@"SELECT * FROM systemmsg"];
        //            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
        while ([set next]) {
            LEFTValue *value = [[LEFTValue alloc] init];
            value.identifier = [NSString stringWithFormat:@"sys_%ld", [set longForColumn:@"guuid"]];
            value.type = 2;
            value.updateTime = [set longForColumn:@"dtime"];
            value.content = [set stringForColumn:@"contentex"];
            
            [weakImport.engine importValue:value];
//            NSLog(@"sys import value <%@>", value);
        }
    };
    
    LEFTSQLDataImporter *tribeImportor = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    weakImport = tribeImportor;
    tribeImportor.dbPath = @"/Users/Leo/Documents/imchatdb/tmmsghis.db";
    tribeImportor.importProcess = ^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:@"SELECT * FROM tribemsg"];
        //            NSUInteger count = [database intForQuery:@"SELECT COUNT(*) FROM instantmsg"];
        while ([set next]) {
            LEFTValue *value = [[LEFTValue alloc] init];
            value.identifier = [NSString stringWithFormat:@"tm_%ld", [set longForColumn:@"guuid"]];
            value.type = 3;
            value.updateTime = [set longForColumn:@"dtime"];
            value.content = [set stringForColumn:@"content"];
            
            [weakImport.engine importValue:value];
//            NSLog(@"tribe import value <%@>", value);
        }
    };
    
    [self.fulltextEngine startImporter:importor];
    [self.fulltextEngine startImporter:sysImportor];
//    [self.fulltextEngine startImporter:tribeImportor];

}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

@end
