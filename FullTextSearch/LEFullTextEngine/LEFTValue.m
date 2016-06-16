//
//  LEFTValue.m
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFTValue.h"

@implementation LEFTValue

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    if (self = [super init]) {
        self.type = [dictionary[@"type"] intValue];
        self.identifier = dictionary[@"identifier"];
        self.content = dictionary[@"content"];
        self.userInfo = dictionary[@"userInfo"];
    }
    return self;
}

- (NSData *)JSONRepresentation
{
    NSDictionary *userInfoTrans = [self _transUserInfo:self.userInfo] ? : @{};
    NSDictionary *jsonDic = @{@"type": @(self.type),
                              @"identifier": self.identifier ? : @"",
                              @"content": self.content ? : @"",
                              @"userInfo": userInfoTrans};
    NSError *error = nil;
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDic options:0 error:&error];
    return jsonData;
}

- (id)_transUserInfo:(id)userInfo
{
    id result = nil;
    if ([userInfo isKindOfClass:[NSArray class]]) {
        result = [NSMutableArray arrayWithCapacity:[userInfo count]];
        for (id value in userInfo) {
            if ([value isKindOfClass:[NSString class]] ||
                [value isKindOfClass:[NSNumber class]]) {
                [result addObject:value];
            } else if ([value isKindOfClass:[NSArray class]] ||
                       [value isKindOfClass:[NSDictionary class]]) {
                [result addObject:[self _transUserInfo:value]];
            } else {
                [result addObject:[value description]];
            }
        }
        return result;
    } else if ([userInfo isKindOfClass:[NSDictionary class]]) {
        result = [NSMutableDictionary dictionaryWithCapacity:[userInfo count]];
        for (id key in [userInfo allKeys]) {
            id value = [userInfo objectForKey:key];
            if ([value isKindOfClass:[NSString class]] ||
                [value isKindOfClass:[NSNumber class]]) {
                [result setObject:value forKey:key];
            } else if ([value isKindOfClass:[NSArray class]] ||
                       [value isKindOfClass:[NSDictionary class]]) {
                [result setObject:[self _transUserInfo:value] forKey:key];
            } else {
                [result setObject:[value description] forKey:key];
            }
        }
        return result;
    }
    return nil;
}

@end
