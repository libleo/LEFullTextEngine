//
//  LEFTPartcipleWrapper.m
//  FullTextSearch
//
//  Created by Leo on 16/5/25.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFTPartcipleWrapper.h"
#include "Jieba.hpp"
#include "KeywordExtractor.hpp"

#include <iconv.h>

extern "C" {
    short isChn(std::string &string)
    {
        short res = 0;
        
        iconv_t ic = iconv_open("UCS-2", "UTF-8");
        const char *src = string.c_str();
        unsigned long len = strlen(src)*2+1;
        char *dst = (char *)malloc(len);
        if(dst == NULL)
        {
            return 0;
        }
        memset(dst, 0, len);
        char *bin = (char *)src;
        char *bout = dst;
        size_t len_in = strlen(src);
        size_t len_out = len;
        if (ic == nullptr)
        {
            printf("init iconv_t failed\n");
            free(dst);
            return 0;
        }
        long n = iconv(ic, &bin, &len_in, &bout, &len_out);
        
        if (n < 0) {
            printf("iconv failed %s\n", strerror(errno));
            return 0;
        }
        
        unsigned short unichar = dst[0]*256 + dst[1];
        
        if (unichar > 128) {
            res = 1;
        }
        
        free(dst);
        iconv_close(ic);
        
        return res;
    }
}

using namespace std;

@interface LEFTPartcipleWrapper ()
{
    std::unique_ptr<cppjieba::Jieba> m_spJiebaParticple;
    std::unique_ptr<cppjieba::KeywordExtractor> m_spJiebaKeywordExtractor;
}

// 分词库需要的文件路径
@property (nonatomic, copy) NSString *dictPath;
@property (nonatomic, copy) NSString *hmmPath;
@property (nonatomic, copy) NSString *userDictPath;
@property (nonatomic, copy) NSString *idfPath;
@property (nonatomic, copy) NSString *stopWordPath;

@end

@implementation LEFTPartcipleWrapper

- (void)dealloc
{
    m_spJiebaParticple.reset();
    m_spJiebaKeywordExtractor.reset();
}

+ (instancetype)shareInstance
{
    static LEFTPartcipleWrapper *shareInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[LEFTPartcipleWrapper alloc] init];
    });
    return shareInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        [self _init];
    }
    return self;
}

- (void)_init
{
    NSBundle *mainBundle = [NSBundle bundleForClass:[LEFTPartcipleWrapper class]];
    
    self.dictPath = [mainBundle pathForResource:@"dict/jieba.dict" ofType:@"utf8"] ;;
    self.hmmPath = [mainBundle pathForResource:@"dict/hmm_model" ofType:@"utf8"];
    self.userDictPath = [mainBundle pathForResource:@"dict/user.dict" ofType:@"utf8"];
    self.idfPath = [mainBundle pathForResource:@"dict/idf" ofType:@"utf8"];
    self.stopWordPath = [mainBundle pathForResource:@"dict/stop_words" ofType:@"utf8"];
    
#warning 云久提示这里很耗时 考虑初始化子线程
    m_spJiebaParticple.reset(new cppjieba::Jieba([self.dictPath cStringUsingEncoding:NSUTF8StringEncoding],
                                       [self.hmmPath cStringUsingEncoding:NSUTF8StringEncoding],
                                       [self.userDictPath cStringUsingEncoding:NSUTF8StringEncoding]));
    m_spJiebaKeywordExtractor.reset(new cppjieba::KeywordExtractor(*m_spJiebaParticple,
                                                                   [self.idfPath cStringUsingEncoding:NSUTF8StringEncoding],
                                                                   [self.stopWordPath cStringUsingEncoding:NSUTF8StringEncoding]));
}

- (NSArray *)minimumParticpleContent:(NSString *)content
{
    if (content == nil) {
        return @[];
    }
    string cStr = [content cStringUsingEncoding:NSUTF8StringEncoding];
    vector<string> words;
    m_spJiebaParticple->CutSmall(cStr, words, 2);
    
    NSString *tmpStr = nil;
    NSMutableArray *wordsArray = [NSMutableArray arrayWithCapacity:words.size()];
    for (auto word = words.cbegin(); word != words.cend(); word++) {
        tmpStr = [NSString stringWithUTF8String:word->c_str()];
        unichar ch = [tmpStr characterAtIndex:0];
        if ((ch >= 0x4E00 && ch <= 0x9FD5) || // unicode 汉字范围
            (ch >= 0x3041 && ch <= 0x30FF) //　unicode 日语假名
            ) {
            [wordsArray addObject:tmpStr];
        }
//        [wordsArray addObject:tmpStr];
//        if (isChn(tmp) == 1) {
//        }
    }
    return wordsArray;
}

- (NSArray *)particpleContent:(NSString *)content
{
    if (content == nil) {
        return @[];
    }
    string cStr = [content cStringUsingEncoding:NSUTF8StringEncoding];
    vector<string> words;
    m_spJiebaParticple->Cut(cStr, words, true);
    
    NSString *tmpStr = nil;
    NSMutableArray *wordsArray = [NSMutableArray arrayWithCapacity:words.size()];
    for (auto word = words.cbegin(); word != words.cend(); word++) {
        tmpStr = [NSString stringWithUTF8String:word->c_str()];
        [wordsArray addObject:tmpStr];
    }
    return wordsArray;
}

- (NSArray *)extractKeywordsWithContent:(NSString *)content
{
    if (content == nil) {
        return @[];
    }
    const size_t topk = ceilf([content length]/5.0);
    string cStr = [content cStringUsingEncoding:NSUTF8StringEncoding];
    vector<cppjieba::KeywordExtractor::Word> keywordres;
    m_spJiebaKeywordExtractor->Extract(cStr, keywordres, topk);
    
    NSString *tmpStr = nil;
    NSMutableArray *wordsArray = [NSMutableArray arrayWithCapacity:keywordres.size()];
    for (auto keyword = keywordres.cbegin(); keyword != keywordres.cend(); keyword++) {
        tmpStr = [NSString stringWithUTF8String:keyword->word.c_str()];
        [wordsArray addObject:tmpStr];
    }
    return wordsArray;
}

@end
