#import "FacExceptionCatch.h"

BOOL FacTry(void (^block)(void), NSError **error) {
  @try {
    block();
    return YES;
  } @catch (NSException *exception) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:exception.name ?: @"FacException"
                                   code:0
                               userInfo:@{
                                 NSLocalizedDescriptionKey : exception.reason ?: @""
                               }];
    }
    return NO;
  }
}
