
const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const page_allocator = std.heap.page_allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const msgq = @import("message-queue.zig");
const Message = msgq.Message;
const MessageDispatcher = msgq.MessageDispatcher;

const esrc = @import("event-sources.zig");
const EventSourceKind = esrc.EventSourceKind;
const EventSource = esrc.EventSource;

const edsm = @import("edsm.zig");
const Reflex = edsm.Reflex;
const Stage = edsm.Stage;
const StageList = edsm.StageList;
const StageMachine = edsm.StageMachine;

const TestMachine = struct {

    const PrivateData = struct {
        ticks: u64 = 0,
    };
    const period: u32 = 1000; // msec

    fn onHeap(a: Allocator, md: *MessageDispatcher) !*StageMachine {
        var sm = try StageMachine.onHeap(a, md, "TEST-EDSM");
        sm.data = try a.create(PrivateData);
        var pd: *PrivateData = @ptrCast(@alignCast(sm.data));
        pd.ticks = 0;

        _ = try sm.addStage(Stage{.name = "INIT", .enter = &initEnter, .leave = null});
        _ = try sm.addStage(Stage{.name = "WORK", .enter = &workEnter, .leave = &workLeave});

        var init = &sm.stages.items[0];
        var work = &sm.stages.items[1];

        init.setReflex(EventSourceKind.sm, Message.M0, Reflex{.transition = work});
        work.setReflex(EventSourceKind.tm, Message.T0, Reflex{.action = &workT0});
        work.setReflex(EventSourceKind.sg, Message.S0, Reflex{.action = &workS0});

        return sm;
    }

    fn initEnter(me: *StageMachine) void {
        me.addTimer() catch unreachable;
        me.addSignal(std.os.SIG.INT) catch unreachable;
        me.msgTo(me, Message.M0, null);
    }

    fn workEnter(me: *StageMachine) void {
        var tm: *EventSource = &me.timers.items[0];
        var sg: *EventSource = &me.signals.items[0];
        tm.start(&me.md.eq, period) catch unreachable;
        sg.enable(&me.md.eq) catch unreachable;
        print("Hi! I am '{s}'. Press ^C to stop me.\n", .{me.name});
    }

    fn workT0(me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void {

        var tm: *EventSource = @ptrCast(@alignCast(data));
        var pd: *PrivateData = @ptrCast(@alignCast(me.data));

        _ = src;
        pd.ticks += 1;
        print("tick #{}\n", .{pd.ticks});
        tm.start(&me.md.eq, period) catch unreachable;
    }

    fn workS0(me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void {
        var pd: *PrivateData = @ptrCast(@alignCast(me.data));
        _ = src;
        _ = data;
        print("got SIGINT after {} ticks\n", .{pd.ticks});
        me.msgTo(null, Message.M0, null);
    }

    fn workLeave(me: *StageMachine) void {
        print("Bye! It was '{s}'\n", .{me.name});
    }
};

pub fn main() !void {

    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var md = try MessageDispatcher.onStack(allocator, 5);
    var sm = try TestMachine.onHeap(allocator, &md);
    try sm.run();

    try md.loop();
    md.eq.fini();
    print("that's all\n", .{});
}
