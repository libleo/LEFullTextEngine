//
//  LEFTImportOperation.h
//  FullTextSearch
//
//  Created by leo on 2017/2/9.
//  Copyright © 2017年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LEFTDataImporter.h"

@interface LEFTImportOperation : NSOperation

@property (nonatomic, readonly) id<LEFTDataImporter> importer;

- (instancetype)initWithImporter:(id<LEFTDataImporter>)importer;

@end
