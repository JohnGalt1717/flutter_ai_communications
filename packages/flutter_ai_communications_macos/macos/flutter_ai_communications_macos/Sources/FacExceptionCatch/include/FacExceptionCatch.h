#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// AVAudioEngine installTap / start throw NSException, which Swift `do` does not catch.
BOOL FacTry(void (^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
