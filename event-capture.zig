
const std = @import("std");
const print = std.debug.print;
const EpollEvent = std.os.linux.epoll_event;
const EpollData = std.os.linux.epoll_data;
const epollCreate = std.os.epoll_create1;
const epollCtl = std.os.epoll_ctl;
const epollWait = std.os.epoll_wait;
const EPOLL = std.os.linux.EPOLL;
const FdAlreadyInSet = std.os.EpollCtlError.FileDescriptorAlreadyPresentInSet;

const msgq = @import("message-queue.zig");
const Message = msgq.Message;
const MessageQueue = msgq.MessageQueue;

const esrc = @import("event-sources.zig");
const EventSourceKind = esrc.EventSourceKind;
const EventSource = esrc.EventSource;

const edsm = @import("edsm.zig");
const StageMachine = edsm.StageMachine;

pub const EventQueue = struct {

    fd: i32 = -1,
    mq: *MessageQueue,

    pub fn onStack(mq: *MessageQueue) !EventQueue {
        return EventQueue {
            .fd = try epollCreate(0),
            .mq = mq,
        };
    }

    pub fn fini(self: *EventQueue) void {
        std.os.close(self.fd);
    }

    fn getEventInfo(es: *EventSource, events: u32) !u4 {

//        var seqn: u4 = undefined;
        if (es.readData) |readData| try readData(es);
        _ = events;

        return switch (es.kind) {
            .sm => unreachable,
            .tm => es.seqn,
            .sg => es.seqn,
            .io => 0,
            //{
            //    if (events & (EPOLL.IN))
            //    // bytes avail
            //},
            .fs => 0,
        };
    }

    pub fn wait(self: *EventQueue) !void {

        const max_events = 1;
        var events: [max_events]EpollEvent = undefined;
        const wait_forever = -1;

        const n = epollWait(self.fd, events[0..], wait_forever);

        for (events[0..n]) |ev| {
            const es = @intToPtr(*EventSource, ev.data.ptr);
            const seqn = try getEventInfo(es, ev.events);
            const msg = Message {
                .src = null,
                .dst = es.owner,
                .esk = es.kind,
                .sqn = seqn,
                .ptr = es,
            };
            try self.mq.put(msg);
        }
    }

    const EventKind = enum {
        can_read,
        can_write,
    };

    fn enableEventSource(self: *EventQueue, es: *EventSource, ek: EventKind) !void {

        var em: u32 = if (EventKind.can_read == ek) (EPOLL.IN | EPOLL.RDHUP) else EPOLL.OUT;
        em |= EPOLL.ONESHOT;

        var ee = EpollEvent {
            .events = em,
            .data = EpollData{.ptr = @ptrToInt(es)},
        };

        // emulate FreeBSD kqueue behavior
        epollCtl(self.fd, EPOLL.CTL_ADD, es.id, &ee) catch |err| {
            return switch (err) {
                FdAlreadyInSet => try epollCtl(self.fd, EPOLL.CTL_MOD, es.id, &ee),
                else => err,
            };
        };
    }

    fn disableEventSource(self: *EventQueue, es: *EventSource) !void {
        const ee = EpollEvent {
            .events = 0,
            .data = EpollData{.ptr = @ptrToInt(es)},
        };
        try epollCtl(self.fd, EPOLL.CTL_MOD, es.id, &ee);
    }

    pub fn enableCanRead(self: *EventQueue, es: *EventSource) !void {
        return try enableEventSource(self, es, EventKind.can_read);
    }

    pub fn enableCanWrite(self: *EventQueue, es: *EventSource) !void {
        return try enableEventSource(self, es, EventKind.can_write);
    }
};
