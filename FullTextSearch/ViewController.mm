//
//  ViewController.m
//  FullTextSearch
//
//  Created by Leo on 16/5/20.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "ViewController.h"
#import "LEFullTextEngine.h"
#import "LEFTValue.h"
#import "LEFTSQLDataImporter.h"

#include "rocksdb/db.h"
#include "Jieba.hpp"
#include "KeywordExtractor.hpp"
#include <stdio.h>
#include <string.h>

static char * DICT_PATH;
static char * HMM_PATH;
static char * USER_DICT_PATH;
static char * IDF_PATH;
static char * STOP_WORD_PATH;

using namespace std;

string * format_words(vector<string> &words)
{
    string *tmp = new string;
    for (auto s = words.cbegin(); s != words.cend(); s++) {
        tmp->append("/");
        tmp->append(*s);
    }
    return tmp;
}

char * copy_str(const char *src)
{
    char *dst = (char *)malloc(strlen(src) + 1);
    strcpy(dst, src);
    return dst;
}

@interface ViewController ()

@property (nonatomic, strong) LEFullTextEngine *fulltextEngine;

@end

@implementation ViewController

+ (void)load
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    DICT_PATH = copy_str([[mainBundle pathForResource:@"dict/jieba.dict" ofType:@"utf8"] cStringUsingEncoding:NSUTF8StringEncoding]);
    HMM_PATH = copy_str([[mainBundle pathForResource:@"dict/hmm_model" ofType:@"utf8"] cStringUsingEncoding:NSUTF8StringEncoding]);
    USER_DICT_PATH = copy_str([[mainBundle pathForResource:@"dict/user.dict" ofType:@"utf8"] cStringUsingEncoding:NSUTF8StringEncoding]);
    IDF_PATH = copy_str([[mainBundle pathForResource:@"dict/idf" ofType:@"utf8"] cStringUsingEncoding:NSUTF8StringEncoding]);
    STOP_WORD_PATH = copy_str([[mainBundle pathForResource:@"dict/stop_words" ofType:@"utf8"] cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    clock_t begin = clock();
    self.fulltextEngine = [[LEFullTextEngine alloc] init];
    NSLog(@"init time use %lf", double(clock() - begin)/CLOCKS_PER_SEC);
    
    LEFTSQLDataImporter *importor = [[LEFTSQLDataImporter alloc] initWithEngine:self.fulltextEngine];
    [self.fulltextEngine startImporter:importor];
//    NSArray *words = [self.fulltextEngine.partcipleWrapper extractKeywordsWithContent:@"他来到了网易杭研大厦"];
//    
//    NSLog(@"extract words is %@", words);
//    
//    LEFTValue *ftValue = [[LEFTValue alloc] init];
//    ftValue.type = 6;
//    ftValue.identifier = @"msg_1110001010";
//    ftValue.content = @"我正在测试我的全文索引";
//    ftValue.userInfo = @{@"hello": [NSArray arrayWithObject:[NSData data]]};
//    ftValue.keywords = [self.fulltextEngine.partcipleWrapper extractKeywordsWithContent:ftValue.content];
//        
//    LEFTValue *ftValue2 = [[LEFTValue alloc] init];
//    ftValue2.type = 6;
//    ftValue2.identifier = @"msg_1110001011";
//    ftValue2.content = @"这只是个测试谢谢，你好啊，哈哈哈啦啦啦啦啦一二三四五";
//    ftValue2.keywords = [self.fulltextEngine.partcipleWrapper extractKeywordsWithContent:ftValue.content];
//    
//    [self.fulltextEngine importValues:@[ftValue, ftValue2]];
    
//    NSArray *searchResult = [self.fulltextEngine searchValueWithSentence:@"测试你好"];
//    for (LEFTValue *value in searchResult) {
//        NSLog(@"id:%@ <%d> %@ <> userInfo %@", value.identifier, value.type, value.content, value.userInfo);
//    }
    
//    [self partcipleTest];

}

- (void)partcipleTest
{
    clock_t begin = clock();
    cppjieba::Jieba jieba(DICT_PATH,
                          HMM_PATH,
                          USER_DICT_PATH);
    printf("%lf", double(clock() - begin)/CLOCKS_PER_SEC);
    vector<string> words;
    vector<cppjieba::Word> jiebawords;
    string s;
    string result;
    
    s = "他来到了网易杭研大厦";
    printf("[demo] Cut With HMM\n");
    jieba.Cut(s, words, true);
    printf("%s", format_words(words)->c_str());
    
    printf("[demo] Cut Without HMM\n");
    jieba.Cut(s, words, false);
    printf("%s", format_words(words)->c_str());
    
//    s = "我来到北京清华大学";
//    cout << s << endl;
//    cout << "[demo] CutAll" << endl;
//    jieba.CutAll(s, words);
//    cout << limonp::Join(words.begin(), words.end(), "/") << endl;
//    
//    s = "小明硕士毕业于中国科学院计算所，后在日本京都大学深造";
//    cout << s << endl;
//    cout << "[demo] CutForSearch" << endl;
//    jieba.CutForSearch(s, words);
//    cout << limonp::Join(words.begin(), words.end(), "/") << endl;
//    
//    cout << "[demo] Insert User Word" << endl;
//    jieba.Cut("男默女泪", words);
//    cout << limonp::Join(words.begin(), words.end(), "/") << endl;
//    jieba.InsertUserWord("男默女泪");
//    jieba.Cut("男默女泪", words);
//    cout << limonp::Join(words.begin(), words.end(), "/") << endl;
//    
//    cout << "[demo] CutForSearch Word With Offset" << endl;
//    jieba.CutForSearch(s, jiebawords, true);
//    cout << jiebawords << endl;
//    
//    cout << "[demo] Tagging" << endl;
//    vector<pair<string, string> > tagres;
//    s = "我是拖拉机学院手扶拖拉机专业的。不用多久，我就会升职加薪，当上CEO，走上人生巅峰。";
//    jieba.Tag(s, tagres);
//    cout << s << endl;
//    cout << tagres << endl;;
//    
//    cppjieba::KeywordExtractor extractor(jieba,
//                                         IDF_PATH,
//                                         STOP_WORD_PATH);
//    cout << "[demo] Keyword Extraction" << endl;
//    const size_t topk = 5;
//    vector<cppjieba::KeywordExtractor::Word> keywordres;
//    extractor.Extract(s, keywordres, topk);
//    cout << s << endl;
//    cout << keywordres << endl;
//    return EXIT_SUCCESS;
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

@end
