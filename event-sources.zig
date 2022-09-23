
const std = @import("std");

const timerFd = std.os.timerfd_create;
const timerFdSetTime = std.os.timerfd_settime;
const TimeSpec = std.os.linux.timespec;
const ITimerSpec = std.os.linux.itimerspec;

const signalFd  = std.os.signalfd;
const sigProcMask = std.os.sigprocmask;
const SigSet = std.os.sigset_t;
const SIG = std.os.SIG;
const SigInfo = std.os.linux.signalfd_siginfo;

const edsm = @import("edsm.zig");
const StageMachine = edsm.StageMachine;
const ecap = @import("event-capture.zig");

pub const EventSourceKind = enum {
    sm,
    io,
    sg,
    tm,
    fs,
};

const IoData = struct {
    bytes_avail: u32,
};

const TimerData = struct {
    nexp: u64,
};

const EventSourceData = union(EventSourceKind) {
    sm: void, // *StageMachine = msg src?
    io: IoData,
    sg: SigInfo,
    tm: TimerData,
    fs: void,
};

const ReadDataFnPtr = *const fn(self: *EventSource) anyerror!void;

pub const EventSource = struct {
    kind: EventSourceKind,
    id: i32, // fd in most cases, but not always
    owner: *StageMachine,
    seqn: u4,
    data: EventSourceData,
    readData: ?ReadDataFnPtr = null,

    pub fn getTimerId() !i32 {
        return try timerFd(std.os.CLOCK.REALTIME, 0);
    }

    fn setTimer(id: i32, msec: u32) !void {
        const its = ITimerSpec {
            .it_interval = TimeSpec {
                .tv_sec = 0,
                .tv_nsec = 0,
            },
            .it_value = TimeSpec {
                .tv_sec = msec / 1000,
                .tv_nsec = (msec % 1000) * 1000 * 1000,
            },
        };
        try timerFdSetTime(id, 0, &its, null);
    }

    pub fn start(self: *EventSource, eq: *ecap.EventQueue, msec: u32) !void {
        if (self.kind != EventSourceKind.tm) unreachable;
        try eq.enableCanRead(self);
        try setTimer(self.id, msec);
    }

    pub fn stop(self: *EventSource, eq: *ecap.EventQueue) !void {
        if (self.kind != EventSourceKind.tm) unreachable;
        try setTimer(self.id, 0);
        try eq.disableEventSource(self);
    }

    pub fn readTimerData(self: *EventSource) !void {
        var buf: [8]u8 = undefined;
        _ = try std.os.read(self.id, buf[0..]);
        std.debug.print("{any}\n", .{buf});
    }

    pub fn getSignalId(signo: u6) !i32 {
        var sset: SigSet = std.os.empty_sigset;
        // block the signal
        std.os.linux.sigaddset(&sset, signo);
        sigProcMask(SIG.BLOCK, &sset, null);

        return signalFd(-1, &sset, 0);
    }

    pub fn readSignalData(self: *EventSource) !void {
        var buf: [@sizeOf(SigInfo)]u8 = undefined;
        _ = try std.os.read(self.id, buf[0..]);
    }

    pub fn enable(self: *EventSource, eq: *ecap.EventQueue) !void {
        if (self.kind == EventSourceKind.tm) unreachable;
        try eq.enableCanRead(self);
    }
};
