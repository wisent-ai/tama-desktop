#import "TamaSystemPolicyXPC.h"

#import <EndpointSecurity/EndpointSecurity.h>
#import <Foundation/Foundation.h>
#import <bsm/libbsm.h>
#import <libproc.h>
#import <sys/fcntl.h>

@interface TamaSession : NSObject
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic) pid_t rootPID;
@property(nonatomic, strong) id<TamaSystemPolicyClient> client;
@end
@implementation TamaSession
@end

@class TamaSystemPolicyDaemon;

@interface TamaConnectionHandler : NSObject <TamaSystemPolicyService>
@property(nonatomic, weak) TamaSystemPolicyDaemon *daemon;
@property(nonatomic, weak) NSXPCConnection *connection;
@end

static NSString *stringToken(es_string_token_t token) {
    if (token.data == NULL || token.length == 0) {
        return @"";
    }
    NSString *value = [[NSString alloc] initWithBytes:token.data
                                               length:token.length
                                             encoding:NSUTF8StringEncoding];
    return value ?: @"";
}

static NSString *filePath(const es_file_t *file) {
    return file == NULL ? @"" : stringToken(file->path);
}

static NSString *newPath(const es_file_t *directory, es_string_token_t filename) {
    return [filePath(directory) stringByAppendingPathComponent:stringToken(filename)];
}

static BOOL processBelongsToSession(pid_t pid, pid_t rootPID) {
    if (pid <= 0 || rootPID <= 0) {
        return NO;
    }
    for (NSUInteger depth = 0; depth < 128 && pid > 1; depth++) {
        if (pid == rootPID) {
            return YES;
        }
        struct proc_bsdinfo info = {0};
        int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
        if (size != sizeof(info) || info.pbi_ppid == 0 || info.pbi_ppid == pid) {
            return NO;
        }
        pid = (pid_t)info.pbi_ppid;
    }
    return NO;
}

static NSDictionary *operationForMessage(const es_message_t *message) {
    switch (message->event_type) {
        case ES_EVENT_TYPE_AUTH_EXEC: {
            const es_event_exec_t *event = &message->event.exec;
            NSMutableArray<NSString *> *arguments = [NSMutableArray array];
            uint32_t count = es_exec_arg_count(event);
            for (uint32_t index = 0; index < count; index++) {
                [arguments addObject:stringToken(es_exec_arg(event, index))];
            }
            return @{
                @"operation": @"process_spawn",
                @"target": filePath(event->target->executable),
                @"arguments": @{ @"argv": arguments },
            };
        }
        case ES_EVENT_TYPE_AUTH_OPEN: {
            const es_event_open_t *event = &message->event.open;
            BOOL writes = (event->fflag & FWRITE) != 0;
            return @{
                @"operation": writes ? @"file_write" : @"file_read",
                @"target": filePath(event->file),
                @"arguments": @{ @"fflag": @(event->fflag) },
            };
        }
        case ES_EVENT_TYPE_AUTH_CREATE: {
            const es_event_create_t *event = &message->event.create;
            NSString *target = event->destination_type == ES_DESTINATION_TYPE_EXISTING_FILE
                ? filePath(event->destination.existing_file)
                : newPath(event->destination.new_path.dir, event->destination.new_path.filename);
            return @{
                @"operation": @"file_write",
                @"target": target,
                @"arguments": @{ @"action": @"create" },
            };
        }
        case ES_EVENT_TYPE_AUTH_UNLINK:
            return @{
                @"operation": @"file_write",
                @"target": filePath(message->event.unlink.target),
                @"arguments": @{ @"action": @"unlink" },
            };
        case ES_EVENT_TYPE_AUTH_RENAME: {
            const es_event_rename_t *event = &message->event.rename;
            NSString *destination = event->destination_type == ES_DESTINATION_TYPE_EXISTING_FILE
                ? filePath(event->destination.existing_file)
                : newPath(event->destination.new_path.dir, event->destination.new_path.filename);
            return @{
                @"operation": @"file_write",
                @"target": filePath(event->source),
                @"arguments": @{ @"action": @"rename", @"destination": destination },
            };
        }
        case ES_EVENT_TYPE_AUTH_TRUNCATE:
            return @{
                @"operation": @"file_write",
                @"target": filePath(message->event.truncate.target),
                @"arguments": @{ @"action": @"truncate" },
            };
        default:
            return nil;
    }
}

static void respondToEvent(es_client_t *client, const es_message_t *message, BOOL allow) {
    if (message->event_type == ES_EVENT_TYPE_AUTH_OPEN) {
        uint32_t flags = allow ? (uint32_t)message->event.open.fflag : 0;
        es_respond_flags_result(client, message, flags, false);
    } else {
        es_respond_auth_result(
            client,
            message,
            allow ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY,
            false
        );
    }
}

@interface TamaSystemPolicyDaemon : NSObject <NSXPCListenerDelegate>
@property(nonatomic) es_client_t *endpointClient;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMapTable<NSXPCConnection *, TamaSession *> *sessions;
@property(nonatomic, strong) NSHashTable<NSXPCConnection *> *networkFilters;
- (BOOL)startEndpointSecurity:(NSError **)error;
- (void)attachSession:(NSDictionary *)payload
           connection:(NSXPCConnection *)connection
             withReply:(void (^)(NSDictionary *response))reply;
- (void)detachConnection:(NSXPCConnection *)connection;
- (BOOL)authorizeMessage:(const es_message_t *)message;
- (BOOL)authorizeOperation:(NSDictionary *)operation pid:(pid_t)pid;
- (void)registerNetworkFilter:(NSXPCConnection *)connection;
@end

@implementation TamaSystemPolicyDaemon

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _lock = [[NSLock alloc] init];
        _sessions = [NSMapTable weakToStrongObjectsMapTable];
        _networkFilters = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (BOOL)startEndpointSecurity:(NSError **)error {
    __weak TamaSystemPolicyDaemon *weakSelf = self;
    es_new_client_result_t result = es_new_client(&_endpointClient, ^(
        es_client_t *client,
        const es_message_t *message
    ) {
        TamaSystemPolicyDaemon *strongSelf = weakSelf;
        respondToEvent(client, message, strongSelf != nil && [strongSelf authorizeMessage:message]);
    });
    if (result != ES_NEW_CLIENT_RESULT_SUCCESS) {
        NSString *reason = nil;
        switch (result) {
            case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
                reason = @"Endpoint Security entitlement is not authorized for this signing team";
                break;
            case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
                reason = @"Full Disk Access is required for the Tama system policy daemon";
                break;
            case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
                reason = @"Tama system policy daemon must run as root";
                break;
            case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
                reason = @"macOS has reached its Endpoint Security client limit";
                break;
            default:
                reason = [NSString stringWithFormat:@"es_new_client failed with status %u", result];
                break;
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ai.wisent.tama.system-policy"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
    es_event_type_t events[] = {
        ES_EVENT_TYPE_AUTH_EXEC,
        ES_EVENT_TYPE_AUTH_OPEN,
        ES_EVENT_TYPE_AUTH_CREATE,
        ES_EVENT_TYPE_AUTH_UNLINK,
        ES_EVENT_TYPE_AUTH_RENAME,
        ES_EVENT_TYPE_AUTH_TRUNCATE,
    };
    es_return_t subscription = es_subscribe(
        _endpointClient,
        events,
        sizeof(events) / sizeof(events[0])
    );
    if (subscription != ES_RETURN_SUCCESS) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ai.wisent.tama.system-policy"
                                         code:subscription
                                     userInfo:@{NSLocalizedDescriptionKey: @"Endpoint Security event subscription failed"}];
        }
        es_delete_client(_endpointClient);
        _endpointClient = NULL;
        return NO;
    }
    es_clear_cache(_endpointClient);
    return YES;
}

- (BOOL)listener:(NSXPCListener *)listener
shouldAcceptNewConnection:(NSXPCConnection *)connection {
    TamaConnectionHandler *handler = [[TamaConnectionHandler alloc] init];
    handler.daemon = self;
    handler.connection = connection;
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TamaSystemPolicyService)];
    connection.exportedObject = handler;
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TamaSystemPolicyClient)];
    __weak TamaSystemPolicyDaemon *weakSelf = self;
    __weak NSXPCConnection *weakConnection = connection;
    connection.invalidationHandler = ^{
        NSXPCConnection *strongConnection = weakConnection;
        if (strongConnection != nil) {
            [weakSelf detachConnection:strongConnection];
        }
    };
    [connection resume];
    return YES;
}

- (void)attachSession:(NSDictionary *)payload
           connection:(NSXPCConnection *)connection
             withReply:(void (^)(NSDictionary *response))reply {
    NSString *identifier = payload[@"sessionId"];
    NSNumber *root = payload[@"rootPid"];
    if (![identifier isKindOfClass:NSString.class] || ![root isKindOfClass:NSNumber.class]
        || identifier.length == 0 || root.intValue <= 0) {
        reply(@{ @"ok": @NO, @"error": @"Invalid session attachment" });
        return;
    }
    TamaSession *session = [[TamaSession alloc] init];
    session.sessionID = identifier;
    session.rootPID = root.intValue;
    session.client = [connection remoteObjectProxyWithErrorHandler:^(__unused NSError *error) {}];
    [self.lock lock];
    [self.sessions setObject:session forKey:connection];
    [self.lock unlock];
    [self.lock lock];
    BOOL networkReady = self.networkFilters.count > 0;
    [self.lock unlock];
    NSMutableArray<NSString *> *capabilities = [@[
        @"process_spawn",
        @"file_read",
        @"file_write",
    ] mutableCopy];
    if (networkReady) {
        [capabilities addObject:@"network_connect"];
    }
    reply(@{
        @"ok": @YES,
        @"backend": @"macos-endpoint-security",
        @"capabilities": capabilities,
    });
}

- (void)detachConnection:(NSXPCConnection *)connection {
    [self.lock lock];
    BOOL removedNetworkFilter = [self.networkFilters containsObject:connection];
    [self.networkFilters removeObject:connection];
    [self.sessions removeObjectForKey:connection];
    NSArray<TamaSession *> *sessions = self.sessions.objectEnumerator.allObjects;
    [self.lock unlock];
    if (removedNetworkFilter) {
        for (TamaSession *session in sessions) {
            [session.client backendError:@"Tama Network Extension disconnected"];
        }
    }
}

- (void)registerNetworkFilter:(NSXPCConnection *)connection {
    [self.lock lock];
    [self.networkFilters addObject:connection];
    [self.lock unlock];
}

- (BOOL)authorizeMessage:(const es_message_t *)message {
    pid_t pid = audit_token_to_pid(message->process->audit_token);
    NSDictionary *operation = operationForMessage(message);
    return operation != nil && [self authorizeOperation:operation pid:pid];
}

- (BOOL)authorizeOperation:(NSDictionary *)operation pid:(pid_t)pid {
    [self.lock lock];
    NSArray<TamaSession *> *snapshot = self.sessions.objectEnumerator.allObjects;
    [self.lock unlock];
    TamaSession *matching = nil;
    for (TamaSession *session in snapshot) {
        if (processBelongsToSession(pid, session.rootPID)) {
            matching = session;
            break;
        }
    }
    if (matching == nil) {
        return YES;
    }
    NSMutableDictionary *request = [operation mutableCopy];
    request[@"pid"] = @(pid);
    __block NSString *decision = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [matching.client authorizeOperation:request withReply:^(NSString *value) {
        decision = [value copy];
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC);
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        return NO;
    }
    return [decision isEqualToString:@"pass"] || [decision isEqualToString:@"allow"];
}

@end

@implementation TamaConnectionHandler
- (void)attachSession:(NSDictionary *)session
            withReply:(void (^)(NSDictionary *response))reply {
    [self.daemon attachSession:session connection:self.connection withReply:reply];
}
- (void)detachSession:(__unused NSString *)sessionID
            withReply:(void (^)(void))reply {
    [self.daemon detachConnection:self.connection];
    reply();
}
- (void)registerNetworkFilterWithReply:(void (^)(BOOL accepted))reply {
    [self.daemon registerNetworkFilter:self.connection];
    reply(YES);
}
- (void)authorizeNetworkOperation:(NSDictionary *)operation
                         withReply:(void (^)(NSString *decision))reply {
    NSNumber *pid = operation[@"pid"];
    if (![pid isKindOfClass:NSNumber.class]
        || ![operation[@"operation"] isEqual:@"network_connect"]) {
        reply(@"block");
        return;
    }
    reply([self.daemon authorizeOperation:operation pid:pid.intValue]
        ? @"pass"
        : @"block");
}
@end

int main(void) {
    @autoreleasepool {
        TamaSystemPolicyDaemon *daemon = [[TamaSystemPolicyDaemon alloc] init];
        NSError *error = nil;
        if (![daemon startEndpointSecurity:&error]) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return 77;
        }
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:TamaSystemPolicyMachService];
        listener.delegate = daemon;
        [listener resume];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
