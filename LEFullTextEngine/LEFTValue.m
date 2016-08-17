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

- (NSString *)description
{
    NSString *superDes = [super description];
    NSString *des = [NSString stringWithFormat:@"%@ {\n\
                     type: %zd\n\
                     identifier: %@\n\
                     content: %@\n\
                     userInfo: %@\n\
                     tag: %@\n\
                     ",
                     superDes,
                     self.type,
                     self.identifier,
                     self.content,
                     self.userInfo,
                     self.tag];
    return des;
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

- (NSString *)userInfoString
{
    NSDictionary *userInfoTrans = [self _transUserInfo:self.userInfo] ? : @{};
    NSError *error = nil;

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:userInfoTrans options:0 error:&error];
    
    if (error == nil) {
        NSString *res = [NSString stringWithCString:jsonData.bytes encoding:NSUTF8StringEncoding];
        return res;
    } else {
        NSLog(@"trans LEFTValue userInfo error <%@>", [error localizedDescription]);
        return @"";
    }
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
