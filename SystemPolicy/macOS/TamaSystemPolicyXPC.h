#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const TamaSystemPolicyMachService = @"ai.wisent.tama.system-policy";

@protocol TamaSystemPolicyClient
- (void)authorizeOperation:(NSDictionary *)operation
                 withReply:(void (^)(NSString *decision))reply;
- (void)backendError:(NSString *)reason;
@end

@protocol TamaSystemPolicyService
- (void)attachSession:(NSDictionary *)session
            withReply:(void (^)(NSDictionary *response))reply;
- (void)detachSession:(NSString *)sessionID
            withReply:(void (^)(void))reply;
- (void)registerNetworkFilterWithReply:(void (^)(BOOL accepted))reply;
- (void)authorizeNetworkOperation:(NSDictionary *)operation
                         withReply:(void (^)(NSString *decision))reply;
@end

NS_ASSUME_NONNULL_END
