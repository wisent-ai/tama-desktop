#import "TamaSystemPolicyXPC.h"

#import <Foundation/Foundation.h>

static NSString *const TamaSystemPolicySchema = @"ai.wisent.tama.system-policy.v1";

static NSDictionary *readMessage(void) {
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length = getline(&line, &capacity, stdin);
    if (length <= 0) {
        free(line);
        return nil;
    }
    NSData *data = [NSData dataWithBytesNoCopy:line length:(NSUInteger)length freeWhenDone:YES];
    NSError *error = nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

@interface TamaSystemPolicyProxy : NSObject <TamaSystemPolicyClient>
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, strong) NSLock *outputLock;
@property(nonatomic, strong) NSCondition *decisionCondition;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *decisions;
@property(nonatomic) NSTimeInterval decisionTimeout;
- (void)emitMessage:(NSDictionary *)message;
- (void)acceptDecision:(NSDictionary *)message;
@end

@implementation TamaSystemPolicyProxy

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _outputLock = [[NSLock alloc] init];
        _decisionCondition = [[NSCondition alloc] init];
        _decisions = [NSMutableDictionary dictionary];
        _decisionTimeout = NSProcessInfo.processInfo.environment[@"TAMA_SYSTEM_POLICY_DECISION_TIMEOUT_SECONDS"].doubleValue;
        if (_decisionTimeout <= 0) {
            _decisionTimeout = 15;
        }
    }
    return self;
}

- (void)emitMessage:(NSDictionary *)message {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:&error];
    if (data == nil) {
        return;
    }
    [self.outputLock lock];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    [self.outputLock unlock];
}

- (void)authorizeOperation:(NSDictionary *)operation
                 withReply:(void (^)(NSString *decision))reply {
    NSString *requestID = NSUUID.UUID.UUIDString.lowercaseString;
    NSMutableDictionary *request = [@{
        @"schema": TamaSystemPolicySchema,
        @"type": @"pre_operation",
        @"sessionId": self.sessionID,
        @"requestId": requestID,
        @"observation": @{ @"source": @"endpoint-security" },
    } mutableCopy];
    [request addEntriesFromDictionary:operation];
    [self emitMessage:request];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:self.decisionTimeout];
    [self.decisionCondition lock];
    while (self.decisions[requestID] == nil && [deadline timeIntervalSinceNow] > 0) {
        [self.decisionCondition waitUntilDate:deadline];
    }
    NSString *decision = self.decisions[requestID] ?: @"block";
    [self.decisions removeObjectForKey:requestID];
    [self.decisionCondition unlock];
    reply(decision);
}

- (void)backendError:(NSString *)reason {
    [self emitMessage:@{
        @"schema": TamaSystemPolicySchema,
        @"type": @"error",
        @"sessionId": self.sessionID,
        @"error": reason,
    }];
}

- (void)acceptDecision:(NSDictionary *)message {
    NSString *requestID = message[@"requestId"];
    NSString *decision = message[@"decision"];
    if (![requestID isKindOfClass:NSString.class]
        || ![decision isKindOfClass:NSString.class]) {
        return;
    }
    [self.decisionCondition lock];
    self.decisions[requestID] = decision;
    [self.decisionCondition broadcast];
    [self.decisionCondition unlock];
}

@end

int main(void) {
    @autoreleasepool {
        NSDictionary *attach = readMessage();
        if (![attach[@"schema"] isEqual:TamaSystemPolicySchema]
            || ![attach[@"type"] isEqual:@"attach"]
            || ![attach[@"sessionId"] isKindOfClass:NSString.class]
            || ![attach[@"rootPid"] isKindOfClass:NSNumber.class]) {
            return 64;
        }

        TamaSystemPolicyProxy *proxy = [[TamaSystemPolicyProxy alloc] init];
        proxy.sessionID = attach[@"sessionId"];
        NSXPCConnection *connection = [[NSXPCConnection alloc]
            initWithMachServiceName:TamaSystemPolicyMachService
            options:NSXPCConnectionPrivileged];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TamaSystemPolicyService)];
        connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TamaSystemPolicyClient)];
        connection.exportedObject = proxy;
        [connection resume];

        dispatch_semaphore_t attached = dispatch_semaphore_create(0);
        __block NSDictionary *attachmentResponse = nil;
        __block NSString *attachmentError = nil;
        id<TamaSystemPolicyService> service = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            attachmentError = error.localizedDescription;
            dispatch_semaphore_signal(attached);
        }];
        [service attachSession:attach withReply:^(NSDictionary *response) {
            attachmentResponse = response;
            dispatch_semaphore_signal(attached);
        }];
        if (dispatch_semaphore_wait(
            attached,
            dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)
        ) != 0) {
            attachmentError = @"Timed out connecting to the privileged Tama system policy daemon";
        }
        if (![attachmentResponse[@"ok"] boolValue]) {
            [proxy emitMessage:@{
                @"schema": TamaSystemPolicySchema,
                @"type": @"error",
                @"sessionId": proxy.sessionID,
                @"error": attachmentError ?: attachmentResponse[@"error"] ?: @"Privileged Tama system policy daemon is unavailable",
            }];
            [connection invalidate];
            return 77;
        }
        [proxy emitMessage:@{
            @"schema": TamaSystemPolicySchema,
            @"type": @"ready",
            @"sessionId": proxy.sessionID,
            @"backend": attachmentResponse[@"backend"] ?: @"macos-endpoint-security",
            @"capabilities": attachmentResponse[@"capabilities"] ?: @[],
        }];

        while (true) {
            NSDictionary *message = readMessage();
            if (message == nil) {
                break;
            }
            if (![message[@"schema"] isEqual:TamaSystemPolicySchema]
                || ![message[@"sessionId"] isEqual:proxy.sessionID]) {
                continue;
            }
            if ([message[@"type"] isEqual:@"decision"]) {
                [proxy acceptDecision:message];
            } else if ([message[@"type"] isEqual:@"detach"]) {
                dispatch_semaphore_t detached = dispatch_semaphore_create(0);
                [service detachSession:proxy.sessionID withReply:^{
                    dispatch_semaphore_signal(detached);
                }];
                dispatch_semaphore_wait(
                    detached,
                    dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)
                );
                break;
            }
        }
        [connection invalidate];
    }
    return 0;
}
