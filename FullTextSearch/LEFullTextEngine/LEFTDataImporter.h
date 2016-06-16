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

- (void)start;
- (void)pause;
- (void)cancel;
- (void)stop;

@end

#endif /* LEFTDataImporter_h */
