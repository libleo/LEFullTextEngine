//
//  LEFTSQLDataImporter.h
//  FullTextSearch
//
//  Created by Leo on 16/6/12.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <LEFullTextEngine/LEFullTextEngine.h>
#import "FMDB.h"

@interface LEFTSQLDataImporter : NSObject <LEFTDataImporter>

@property (nonatomic, copy) NSString *dbPath;
@property (nonatomic, copy) void(^importProcess)(FMDatabase *db);

@end
