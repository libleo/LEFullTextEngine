//
//  LEFTValue.h
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LEFTValue : NSObject

@property (nonatomic, assign) int32_t type; // 自定义类型
@property (nonatomic, copy) NSString *identifier; // 自定义custom id
@property (nonatomic, copy) NSString *content; // 全文内容
@property (nonatomic, strong) NSArray *keywords; // 关联的keywords
@property (nonatomic, strong) NSDictionary *userInfo; // 附加信息
@property (nonatomic, assign) NSTimeInterval updateTime;
@property (nonatomic, copy) NSString *tag;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSData *)JSONRepresentation;
- (NSString *)userInfoString;

@end
