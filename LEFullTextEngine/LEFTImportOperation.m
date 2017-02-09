//
//  LEFTImportOperation.m
//  FullTextSearch
//
//  Created by leo on 2017/2/9.
//  Copyright © 2017年 leo. All rights reserved.
//

#import "LEFTImportOperation.h"

@implementation LEFTImportOperation

@synthesize importer = _importer;

- (void)dealloc
{
    NSLog(@"LEFTImportOperation is deallocating...");
}

- (instancetype)initWithImporter:(id<LEFTDataImporter>)importer
{
    if (self = [super init]) {
        _importer = importer;
    }
    return self;
}

- (void)main
{
    [self.importer start];
}

- (void)cancel
{
    NSLog(@"LEFTImportOperation cancel...");
    [self.importer cancel];
    [super cancel];
}

@end
