// Endpoint Security helpers for tama-system-policy-daemon.m, imported by it alone.
#import <EndpointSecurity/EndpointSecurity.h>
#import <Foundation/Foundation.h>
#import <bsm/libbsm.h>
#import <libproc.h>
#import <sys/fcntl.h>

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
