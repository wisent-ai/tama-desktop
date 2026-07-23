#import "TamaSystemPolicyXPC.h"

#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <bsm/libbsm.h>

static pid_t processIdentifierForFlow(NEFilterFlow *flow) {
    NSData *tokenData = flow.sourceProcessAuditToken ?: flow.sourceAppAuditToken;
    if (tokenData.length != sizeof(audit_token_t)) {
        return 0;
    }
    audit_token_t token = {0};
    [tokenData getBytes:&token length:sizeof(token)];
    return audit_token_to_pid(token);
}

@interface TamaNetworkFilterProvider : NEFilterDataProvider
@property(nonatomic, strong) NSXPCConnection *policyConnection;
@end

@implementation TamaNetworkFilterProvider

- (void)startFilterWithCompletionHandler:(void (^)(NSError *error))completionHandler {
    self.policyConnection = [[NSXPCConnection alloc]
        initWithMachServiceName:TamaSystemPolicyMachService
        options:NSXPCConnectionPrivileged];
    self.policyConnection.remoteObjectInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(TamaSystemPolicyService)];
    [self.policyConnection resume];
    id<TamaSystemPolicyService> service = [self.policyConnection
        remoteObjectProxyWithErrorHandler:^(NSError *error) {
            completionHandler(error);
        }];
    [service registerNetworkFilterWithReply:^(BOOL accepted) {
        if (accepted) {
            completionHandler(nil);
        } else {
            completionHandler([NSError
                errorWithDomain:@"ai.wisent.tama.network-filter"
                code:1
                userInfo:@{NSLocalizedDescriptionKey: @"Tama policy daemon rejected the network filter"}]);
        }
    }];
}

- (void)stopFilterWithReason:(__unused NEProviderStopReason)reason
           completionHandler:(void (^)(void))completionHandler {
    [self.policyConnection invalidate];
    self.policyConnection = nil;
    completionHandler();
}

- (NEFilterNewFlowVerdict *)handleNewFlow:(NEFilterFlow *)flow {
    pid_t pid = processIdentifierForFlow(flow);
    if (pid <= 0) {
        return [NEFilterNewFlowVerdict allowVerdict];
    }
    NSString *target = flow.URL.absoluteString ?: @"";
    NSMutableDictionary *arguments = [NSMutableDictionary dictionary];
    arguments[@"direction"] = @(flow.direction);
    if ([flow isKindOfClass:NEFilterSocketFlow.class]) {
        NEFilterSocketFlow *socketFlow = (NEFilterSocketFlow *)flow;
        target = socketFlow.remoteHostname
            ?: socketFlow.remoteEndpoint.description
            ?: target;
        arguments[@"socketFamily"] = @(socketFlow.socketFamily);
        arguments[@"socketType"] = @(socketFlow.socketType);
        arguments[@"socketProtocol"] = @(socketFlow.socketProtocol);
    }
    NSDictionary *operation = @{
        @"operation": @"network_connect",
        @"target": target,
        @"arguments": arguments,
        @"pid": @(pid),
    };
    __weak TamaNetworkFilterProvider *weakSelf = self;
    id<TamaSystemPolicyService> service = [self.policyConnection
        remoteObjectProxyWithErrorHandler:^(__unused NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf resumeFlow:flow withVerdict:[NEFilterNewFlowVerdict dropVerdict]];
            });
        }];
    [service authorizeNetworkOperation:operation withReply:^(NSString *decision) {
        BOOL allow = [decision isEqualToString:@"pass"]
            || [decision isEqualToString:@"allow"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf resumeFlow:flow withVerdict:allow
                ? [NEFilterNewFlowVerdict allowVerdict]
                : [NEFilterNewFlowVerdict dropVerdict]];
        });
    }];
    return [NEFilterNewFlowVerdict pauseVerdict];
}

- (NEFilterDataVerdict *)handleInboundDataFromFlow:(__unused NEFilterFlow *)flow
                             readBytesStartOffset:(__unused NSUInteger)offset
                                         readBytes:(__unused NSData *)readBytes {
    return [NEFilterDataVerdict allowVerdict];
}

- (NEFilterDataVerdict *)handleOutboundDataFromFlow:(__unused NEFilterFlow *)flow
                              readBytesStartOffset:(__unused NSUInteger)offset
                                          readBytes:(__unused NSData *)readBytes {
    return [NEFilterDataVerdict allowVerdict];
}

- (NEFilterDataVerdict *)handleInboundDataCompleteForFlow:(__unused NEFilterFlow *)flow {
    return [NEFilterDataVerdict allowVerdict];
}

- (NEFilterDataVerdict *)handleOutboundDataCompleteForFlow:(__unused NEFilterFlow *)flow {
    return [NEFilterDataVerdict allowVerdict];
}

@end

int main(__unused int argc, __unused char *argv[]) {
    @autoreleasepool {
        [NEProvider startSystemExtensionMode];
    }
    dispatch_main();
}
