#import <Foundation/Foundation.h>
#import "RegexKitLite.h"
#import "XMLParser.h"

BOOL raw_output;

@interface Stripper : NSObject {
}
- (NSString *)strip:(NSString *)text;
@end

Stripper *stripper;

@interface Article : NSObject {
  NSString *title, *body;
}

@property (retain) NSString *title;
@property (retain) NSString *body;

- (BOOL)isDesirable;
- (void)writeStdout;

@end

@interface XMLProcessor : XMLParser {
  Article *curArticle;
  NSMutableString *curText;
  time_t tStart;
  time_t tLast;
  int processed;
  BOOL charsAreRelevantToMyInterests;
  NSAutoreleasePool *pool;
  FILE *file;
  float movingAvg;
}

@end

@implementation Article

@synthesize title;
@synthesize body;

const int START_HEADING = 1;
const int START_TEXT = 2;
const int END_TEXT = 3;

- (BOOL)isDesirable {
  return (([title rangeOfString:@":"].location == NSNotFound) &&
          ([title rangeOfString:@"/"].location == NSNotFound) &&
          ([body rangeOfString:@"#redirect" options:NSCaseInsensitiveSearch].location == NSNotFound));
}

- (void)writeStdout {
  NSString *output = raw_output ? self.body : [stripper strip:self.body];
  printf("%c%s%d%c%s%c",
         START_HEADING,
         [title UTF8String],
         [output lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
         START_TEXT,
         [output UTF8String]
         END_TEXT);
}

- (void)dealloc {
  [title release];
  [body release];
  [super dealloc];
}

@end

/* Stripper */

@implementation Stripper

- (NSString *)stripTags:(NSString *)open close:(NSString *)close text:(NSString *)text {
  NSRange closing, opening;
  while((closing = [text rangeOfString:close]).location != NSNotFound) {
    opening = [text rangeOfString:open options:NSBackwardsSearch range:NSMakeRange(0, closing.location)];
    
    if(opening.location != NSNotFound && opening.location < closing.location)
      text = [text stringByReplacingCharactersInRange:NSMakeRange(opening.location, closing.location + closing.length - opening.location)
                   withString:@""];
    else
      break;
  }
  
  return text;
}

- (NSString *)stripExtraNL:(NSString *)txt {
  return [txt stringByReplacingOccurrencesOfRegex:@"\n+" withString:@"\n"];
}

- (NSString *)stripComments:(NSString *)txt {
  return [self stripTags:@"<!--" close:@"-->" text:txt];
}

- (NSString *)strip:(NSString *)txt {
  return [self stripExtraNL:[self stripComments:txt]];
}

@end

@implementation XMLProcessor

- init:(const XML_Char *)encoding:(XML_Char)sep:(int)bs:(unsigned int)parsemask {
  [super init:encoding :sep :bs :parsemask];
  time(&tStart);
  time(&tLast);
  movingAvg = 0.0;
  processed = 0;
  charsAreRelevantToMyInterests = NO;
  file = NULL;
  curText = nil;
  curArticle = nil;
  pool = nil;
  return self;
}

- (void)printStats {
  time_t now;
  time(&now);
  float t = (float) (now - tStart);
  
  float rate = ((float)processed)/t;
  
  if(now - tLast > 0)
    movingAvg = 0.8 * movingAvg + 0.2 * (3000.0/(now-tLast));
  
  tLast = now;
  
  NSLog(@"Processed %d articles at a rate of %.2f/sec (%.2f)", processed, rate, movingAvg);
}

- (void)startElement:(const XML_Char *)qname :(const XML_Char **)atts {
  NSString *elementName = [NSString stringWithUTF8String:qname];
  
  if([elementName isEqualToString:@"page"]) {
    if(processed % 3000 ==  0)
      [self printStats];
  
    if(curArticle && [curArticle isDesirable]) {
      @try {
        [curArticle writeStdout];
      } @catch (NSException *e) {
        NSLog(@"ERROR saving %@: %@", [curArticle title], [e description]);
      }
    }
      
    
    [pool release];
    pool = [NSAutoreleasePool new];
    
    curArticle = [[Article new] autorelease];
    processed++;
  } else if([elementName isEqualToString:@"title"] || [elementName isEqualToString:@"text"]) {
    charsAreRelevantToMyInterests = YES;
    curText = [NSMutableString new];
  }
}

- (void)endElement:(const XML_Char *)qname {
  NSString *elementName = [NSString stringWithUTF8String:qname];
  
  if([elementName isEqualToString:@"title"])
    [curArticle setTitle:curText];
  else if([elementName isEqualToString:@"text"])
    [curArticle setBody:curText];
  
    
  if(charsAreRelevantToMyInterests) {
    [curText release];    
    charsAreRelevantToMyInterests = NO;
  }
}

- (void)characters:(const XML_Char *)s :(int)len {
  if(charsAreRelevantToMyInterests) {
    NSString *chars = [[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding];
    [curText appendString:chars];
    [chars release];
  }
}

- (int)dataRead:(char *)buff :(int)buflen {
  int len;

  len = fread(buff, sizeof(char), buflen, file ? file : stdin);
  return len;
}

- (void)test {
  Stripper *s = [[Stripper new] autorelease];
  
  NSMutableString *str = [NSMutableString new];
  char buf[512];
  size_t read;
  while(read = fread(buf, 1, 512, file ? file : stdin)) {
    [str appendString:[NSString stringWithCString:buf length:read]];
  }
  
  NSString *stripped = [s strip:str];
  fwrite([stripped UTF8String], 1, [stripped lengthOfBytesUsingEncoding:NSUTF8StringEncoding], stdout);
}

- (void)useFile:(NSString *)f {
  file = fopen([f UTF8String], "r");
}

@end

int main(int argc, char **argv) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  
  if(argc == 2 && !strcmp(argv[1], "-raw"))
    raw_output = YES;
    
  stripper = [Stripper new];
  XMLProcessor *parser = [[XMLProcessor alloc] init:"utf-8" :'|' :8192:
                                  (XML_PARSE_STARTELEM | XML_PARSE_DISABLE_NS | XML_PARSE_ENDELEM | XML_PARSE_CHARACTERS)];
  /* [parser useFile:@"file.txt"]; */
  [parser start];
  
  [pool release];
}
