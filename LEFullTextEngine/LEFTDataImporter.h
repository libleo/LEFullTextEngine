//
//  LEFTDataImporter.h
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

@class LEFullTextEngine;

#ifndef LEFTDataImporter_h
#define LEFTDataImporter_h

typedef enum : int32_t {
    LEFTDataImporterStatusPending,
    LEFTDataImporterStatusRunning,
    LEFTDataImporterStatusPause,
    LEFTDataImporterStatusFinished,
} LEFTDataImporterStatus;

@protocol LEFTDataImporter <NSObject>

- (instancetype)initWithEngine:(LEFullTextEngine *)engine;

@property (assign) LEFTDataImporterStatus status;

- (LEFullTextEngine *)engine;

- (void)start;
- (void)pause;
- (void)resume;
- (void)cancel;

@end

#endif /* LEFTDataImporter_h */
