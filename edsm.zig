
const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const msgq = @import("message-queue.zig");
const Message = msgq.Message;
const MessageQueue = msgq.MessageQueue;
const MessageDispatcher = msgq.MessageDispatcher;

const esrc = @import("event-sources.zig");
const EventSourceKind = esrc.EventSourceKind;
const EventSource = esrc.EventSource;

const reactFnPtr = *const fn (me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void;
const enterFnPtr = *const fn (me: *StageMachine) void;
const leaveFnPtr = enterFnPtr;

const ReflexKind = enum {
    action,
    transition
};

pub const Reflex = union(ReflexKind) {
    action: reactFnPtr,
    transition: *Stage,
};

pub const Stage = struct {

    /// number of rows in reflex matrix
    const nrows = @typeInfo(EventSourceKind).Enum.fields.len;
    const esk_tags = "MDSTF";
    /// number of columns in reflex matrix
    const ncols = 16;
    /// name of a stage
    name: []const u8,
    /// called when machine enters the stage
    enter: ?enterFnPtr = null,
    /// called when machine leaves the stage
    leave: ?leaveFnPtr = null,

    /// reflex matrix
    /// row 0: M0 M1 M2 ... M15 : internal messages
    /// row 1: D0 D1 D2         : i/o (POLLIN, POLLOUT, POLLERR)
    /// row 2: S0 S1 S2 ... S15 : signals
    /// row 3: T0 T1 T2 ... T15 : timers
    /// row 4: F0.............. : file system events
    reflexes: [nrows][ncols]?Reflex = [nrows][ncols]?Reflex {
        [_]?Reflex{null} ** ncols,
        [_]?Reflex{null} ** ncols,
        [_]?Reflex{null} ** ncols,
        [_]?Reflex{null} ** ncols,
        [_]?Reflex{null} ** ncols,
    },

    pub fn setReflex(self: *Stage, esk: EventSourceKind, seqn: u4, refl: Reflex) void {
        const row: u8 = @intFromEnum(esk);
        const col: u8 = seqn;
        self.reflexes[row][col] = refl;
    }
};

pub const StageList = std.ArrayList(Stage);
pub const EventSourceList = std.ArrayList(EventSource);

const StageMachineError = error {
    is_running,
};

pub const StageMachine = struct {

    name: []const u8,
    is_running: bool = false,
    stages: StageList = undefined,
    current_stage: *Stage = undefined,

    md: *msgq.MessageDispatcher,
    timers: EventSourceList = undefined,
    signals: EventSourceList = undefined,
    data: ?*anyopaque = null,

    pub fn onHeap(a: Allocator, md: *MessageDispatcher, name: []const u8) !*StageMachine {
        var sm = try a.create(StageMachine);
        sm.name = name;
        sm.is_running = false;
        sm.md = md;
        sm.stages = StageList.init(a);
        sm.timers = EventSourceList.init(a);
        sm.signals = EventSourceList.init(a);
        return sm;
    }

    pub fn addStage(self: *StageMachine, st: Stage) !*Stage {
        var ptr = try self.stages.addOne();
        ptr.* = st;
        return ptr;
    }

    pub fn addTimer(self: *StageMachine) !void {
        var tm = try self.timers.addOne();
        tm.id = try EventSource.getTimerId();
        tm.kind = EventSourceKind.tm;
        tm.owner = self;
        tm.seqn = @intCast(self.timers.items.len - 1);
        tm.readData = EventSource.readTimerData;
    }

    pub fn addSignal(self: *StageMachine, signo: u6) !void {
        var sg = try self.signals.addOne();
        sg.id = try EventSource.getSignalId(signo);
        sg.kind = EventSourceKind.sg;
        sg.owner = self;
        sg.seqn = @intCast(self.signals.items.len - 1);
        sg.readData = EventSource.readSignalData;
    }

    /// state machine engine
    pub fn reactTo(self: *StageMachine, msg: Message) void {
        const row: u8 = @intFromEnum(msg.esk);
        const col = msg.sqn;
        const current_stage = self.current_stage;
        if (current_stage.reflexes[row][col]) |refl| {
            switch (refl) {
                ReflexKind.action => |func| func(self, msg.src, msg.ptr),
                ReflexKind.transition => |next_stage| {
                    if (current_stage.leave) |func| {
                        func(self);
                    }
                    self.current_stage = next_stage;
                    if (next_stage.enter) |func| {
                        func(self);
                    }
                },
            }
        } else {
            const sender: []const u8 = if (msg.src) |src| src.name else "OS";
            print("\n{s}@{s} : no reflex for '{c}{}'\n", .{self.name, current_stage.name, Stage.esk_tags[row], col});
            print("(sent by {s})\n\n", .{sender});
            unreachable;
        }
    }

    pub fn msgTo(self: *StageMachine, dst: ?*StageMachine, sqn: u4, data: ?*anyopaque) void {
        const msg = Message {
            .src = self,
            .dst = dst,
            .esk = EventSourceKind.sm,
            .sqn = sqn,
            .ptr = data,
        };
        // message buffer is not growable so this will panic
        // when there is no more space left in the buffer
        self.md.mq.put(msg) catch unreachable;
    }

    pub fn run(self: *StageMachine) !void {

        if (self.is_running)
            return StageMachineError.is_running;

        self.current_stage = &self.stages.items[0];
        if (self.current_stage.enter) |hello| {
            hello(self);
        }
        self.is_running = true;
    }
};
