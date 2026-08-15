const r4os = @import("r4os");
const AppApi = struct {
    sys: r4os.r4sys.Context,
    desk: r4os.r4desk.Context,
    draw: r4os.r4draw.Context,
    net: r4os.r4net.Context,
    dev: r4os.r4dev.Context,

    fn init(r4_app: *r4os.App) ?AppApi {
        return .{
            .sys = r4_app.system(),
            .desk = r4_app.desktop() orelse return null,
            .draw = r4_app.drawing() orelse return null,
            .net = r4_app.networkLowLevel() orelse return null,
            .dev = r4_app.devicesLowLevel() orelse return null,
        };
    }
};

const app_bg = r4os.gui.default_palette.face;
const panel_bg = r4os.gui.default_palette.client_bg;
const status_bg: u32 = 0xD8D8D8;
const black = r4os.gui.default_palette.text;

const ICMP_PROTOCOL: u8 = 1;
const ICMP_ECHO_REQUEST: u8 = 8;
const TEST_IDENT: u16 = 0x4E43;
const TEST_SEQ: u16 = 1;

const FocusTarget = enum(usize) {
    ip,
    mask,
    gateway,
    dns,
    defaults,
    test_button,
    apply,
    ok,
    cancel,
};

const focus_items = [_]r4os.gui.FocusItem{
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
};

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var ctx = AppApi.init(r4_app) orelse return r4os.abi.err_no_group;
    var app = App{ .ctx = &ctx };
    return app.run();
}

const App = struct {
    ctx: *AppApi,
    w: i32 = 440,
    h: i32 = 300,
    initialized: bool = false,
    should_exit: bool = false,
    snapshot: r4os.abi.NetConfigSnapshot = .{},
    ip: r4os.gui.TextField(16) = .{},
    mask: r4os.gui.TextField(16) = .{},
    gateway: r4os.gui.TextField(16) = .{},
    dns: r4os.gui.TextField(16) = .{},
    focus: r4os.gui.FocusState = .{ .index = focusIndex(.ip) },
    mouse_capture: r4os.gui.MouseCapture = .{},
    status: [96]u8 = .{0} ** 96,
    dialog_open: bool = false,
    dialog_kind: r4os.gui.MessageKind = .info,
    dialog_title: [32]u8 = .{0} ** 32,
    dialog_message: [96]u8 = .{0} ** 96,

    fn run(self: *App) i32 {
        if (self.ctx.desk.programWindowId() >= 0) return self.runHosted();
        self.ctx.sys.println("NETCFG is a desktop GUI application.");
        self.ctx.sys.println("Please start from Desktop or through GUI launch.");
        return 0;
    }

    fn runHosted(self: *App) i32 {
        _ = self.ctx.desk.guiSetTitle("Network");
        _ = self.ctx.desk.guiSetMinSize(440, 300);
        self.init();
        var info: r4os.abi.GuiWindowInfo = .{};
        _ = self.ctx.desk.guiWindowInfo(&info);
        self.updateMetrics(info);
        self.render();

        while (!self.ctx.sys.programShouldClose() and !self.should_exit) {
            var event: r4os.abi.GuiEvent = .{};
            while (self.ctx.desk.guiPollEvent(&event) > 0) {
                const kind: r4os.abi.GuiEventKind = @enumFromInt(event.kind);
                switch (kind) {
                    .close => return 0,
                    .resize => {
                        _ = self.ctx.desk.guiWindowInfo(&info);
                        self.updateMetrics(info);
                        self.render();
                    },
                    .mouse_down => self.handleMouseDown(event.x, event.y),
                    .mouse_up => self.handleMouseUp(event.x, event.y),
                    .key_down => self.handleKey(@intCast(event.key & 0xFF)),
                    else => {},
                }
            }
            self.ctx.sys.sleepTicks(3);
        }
        return 0;
    }

    fn init(self: *App) void {
        if (self.initialized) return;
        self.reloadSnapshot();
        _ = self.focus.set(focus_items[0..], focusIndex(.ip));
        self.syncFocus();
        self.initialized = true;
    }

    fn reloadSnapshot(self: *App) void {
        const result = self.ctx.net.netConfigGet(&self.snapshot);
        if (result != r4os.abi.net_config_ok) {
            self.setStatus("Network snapshot could not be read.");
            self.setDialog(.failure, "Network", "Snapshot could not be read.");
            self.dialog_open = true;
            return;
        }
        var tmp: [24]u8 = .{0} ** 24;
        self.ip.set(ipText(tmp[0..], self.snapshot.local_ip));
        self.mask.set(ipText(tmp[0..], self.snapshot.netmask));
        self.gateway.set(ipText(tmp[0..], self.snapshot.gateway_ip));
        if ((self.snapshot.flags & r4os.abi.net_config_flag_dns_configured) != 0) {
            self.dns.set(ipText(tmp[0..], self.snapshot.dns_ip));
        } else {
            self.dns.clear();
        }
        self.setStatus("Ready.");
    }

    fn updateMetrics(self: *App, info: r4os.abi.GuiWindowInfo) void {
        const canvas = r4os.gui.Canvas.init(&self.ctx.draw, info);
        self.w = clampI32(canvas.w, 440, 1600);
        self.h = clampI32(canvas.h, 300, 1000);
    }

    fn render(self: *App) void {
        var paint = switch (r4os.app_gui.beginPaintForSize(&self.ctx.draw, self.w, self.h)) {
            .paint => |value| value,
            .failure => return,
        };
        defer paint.discard();
        const canvas = paint.canvas;
        var scratch: [128]u8 = .{0} ** 128;
        self.syncFocus();

        _ = canvas.clear(app_bg);
        self.drawAdapterBox(canvas, scratch[0..]);
        self.drawIpv4Box(canvas, scratch[0..]);
        self.drawButtons(canvas, scratch[0..]);
        _ = canvas.rect(self.statusRect(), status_bg);
        _ = canvas.label(.{
            .rect = self.statusRect().inset(6, 3),
            .text = spanZ(self.status[0..]),
            .fg = black,
            .bg = status_bg,
        }, scratch[0..]);
        if (self.dialog_open) {
            _ = canvas.messageDialog(.{
                .rect = self.dialogRect(),
                .title = spanZ(self.dialog_title[0..]),
                .message = spanZ(self.dialog_message[0..]),
                .kind = self.dialog_kind,
            }, scratch[0..]);
        }
        _ = paint.present();
    }

    fn drawAdapterBox(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        _ = canvas.groupBox(.{ .rect = self.adapterRect(), .title = "Adapter" }, scratch);
        var line: [96]u8 = .{0} ** 96;
        setZ(line[0..], "Name: ");
        if ((self.snapshot.flags & r4os.abi.net_config_flag_adapter_present) != 0) {
            appendZ(line[0..], spanZ(self.snapshot.adapter_name[0..]));
        } else {
            appendZ(line[0..], "no adapter");
        }
        _ = canvas.label(.{ .rect = .{ .x = 24, .y = 34, .w = self.w - 48, .h = 16 }, .text = spanZ(line[0..]), .fg = black, .bg = app_bg }, scratch);

        setZ(line[0..], "Link: ");
        appendZ(line[0..], if ((self.snapshot.flags & r4os.abi.net_config_flag_link_up) != 0) "up" else spanZ(self.snapshot.link[0..]));
        appendZ(line[0..], "   Source: ");
        appendZ(line[0..], spanZ(self.snapshot.source[0..]));
        _ = canvas.label(.{ .rect = .{ .x = 24, .y = 52, .w = self.w - 48, .h = 16 }, .text = spanZ(line[0..]), .fg = black, .bg = app_bg }, scratch);

        setZ(line[0..], "Status: ");
        appendZ(line[0..], spanZ(self.snapshot.last_error[0..]));
        _ = canvas.label(.{ .rect = .{ .x = 24, .y = 70, .w = self.w - 48, .h = 16 }, .text = spanZ(line[0..]), .fg = black, .bg = app_bg }, scratch);
    }

    fn drawIpv4Box(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        _ = canvas.groupBox(.{ .rect = self.ipv4Rect(), .title = "Static IPv4 configuration" }, scratch);
        self.drawField(canvas, scratch, "IPv4 address:", self.ipRect(), &self.ip);
        self.drawField(canvas, scratch, "Netmask:", self.maskRect(), &self.mask);
        self.drawField(canvas, scratch, "Gateway:", self.gatewayRect(), &self.gateway);
        self.drawField(canvas, scratch, "DNS:", self.dnsRect(), &self.dns);
    }

    fn drawField(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, label: []const u8, rect: r4os.gui.Rect, field: anytype) void {
        _ = self;
        _ = canvas.label(.{ .rect = .{ .x = rect.x - 104, .y = rect.y + 4, .w = 96, .h = 16 }, .text = label, .alignment = .right, .fg = black, .bg = app_bg }, scratch);
        _ = field.draw(canvas, rect, scratch);
    }

    fn drawButtons(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        self.drawButton(canvas, scratch, self.defaultsRect(), "Defaults", .defaults, false, false);
        self.drawButton(canvas, scratch, self.testRect(), "Test", .test_button, false, false);
        self.drawButton(canvas, scratch, self.applyRect(), "Apply", .apply, false, false);
        self.drawButton(canvas, scratch, self.okRect(), "OK", .ok, true, false);
        self.drawButton(canvas, scratch, self.cancelRect(), "Cancel", .cancel, false, true);
    }

    fn drawButton(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, rect: r4os.gui.Rect, text: []const u8, target: FocusTarget, is_default: bool, is_cancel: bool) void {
        _ = canvas.button(.{
            .rect = rect,
            .text = text,
            .state = if (self.mouse_capture.isActive(focusIndex(target))) .pressed else .normal,
            .focused = self.hasFocus(target),
            .is_default = is_default,
            .is_cancel = is_cancel,
        }, scratch);
    }

    fn handleMouseDown(self: *App, x: i32, y: i32) void {
        self.mouse_capture.clear();
        if (self.dialog_open) {
            const dialog = self.messageDialog();
            if (dialog.actionAt(x, y) == .ok) {
                self.mouse_capture.begin(100, .submitted);
                self.render();
            }
            return;
        }
        if (self.hitField(x, y)) return;
        if (self.captureButton(x, y, .defaults, self.defaultsRect())) return;
        if (self.captureButton(x, y, .test_button, self.testRect())) return;
        if (self.captureButton(x, y, .apply, self.applyRect())) return;
        if (self.captureButton(x, y, .ok, self.okRect())) return;
        if (self.captureButton(x, y, .cancel, self.cancelRect())) return;
    }

    fn handleMouseUp(self: *App, x: i32, y: i32) void {
        if (self.dialog_open) {
            if (self.mouse_capture.release(100, self.messageDialog().okRect().contains(x, y)) == .submitted) {
                self.dialog_open = false;
                self.render();
            }
            return;
        }
        if (self.releaseButton(x, y, .defaults, self.defaultsRect())) return;
        if (self.releaseButton(x, y, .test_button, self.testRect())) return;
        if (self.releaseButton(x, y, .apply, self.applyRect())) return;
        if (self.releaseButton(x, y, .ok, self.okRect())) return;
        if (self.releaseButton(x, y, .cancel, self.cancelRect())) return;
    }

    fn handleKey(self: *App, key: u8) void {
        if (self.dialog_open) {
            if (self.messageDialog().keyAction(key) == .ok) {
                self.dialog_open = false;
                self.render();
            }
            return;
        }
        if (self.focusedField()) |field| {
            if (key != r4os.gui.Key.tab and key != r4os.gui.Key.shift_tab and key != r4os.gui.Key.enter and key != r4os.gui.Key.escape) {
                if (field.handleClipboardKey(&self.ctx.desk, key)) self.render();
                return;
            }
        }
        const result = self.focus.handleKey(focus_items[0..], key);
        switch (result.action) {
            .changed => {
                self.syncFocus();
                self.render();
            },
            .submitted, .clicked => {
                self.activateFocused();
                self.render();
            },
            .cancelled => {
                self.should_exit = true;
            },
            else => {},
        }
    }

    fn hitField(self: *App, x: i32, y: i32) bool {
        if (self.ipRect().contains(x, y)) return self.setFocus(.ip);
        if (self.maskRect().contains(x, y)) return self.setFocus(.mask);
        if (self.gatewayRect().contains(x, y)) return self.setFocus(.gateway);
        if (self.dnsRect().contains(x, y)) return self.setFocus(.dns);
        return false;
    }

    fn captureButton(self: *App, x: i32, y: i32, target: FocusTarget, rect: r4os.gui.Rect) bool {
        if (!rect.contains(x, y)) return false;
        _ = self.focus.set(focus_items[0..], focusIndex(target));
        self.mouse_capture.begin(focusIndex(target), .clicked);
        self.render();
        return true;
    }

    fn releaseButton(self: *App, x: i32, y: i32, target: FocusTarget, rect: r4os.gui.Rect) bool {
        if (self.mouse_capture.release(focusIndex(target), rect.contains(x, y)) != .clicked) return false;
        self.activate(target);
        self.render();
        return true;
    }

    fn activateFocused(self: *App) void {
        self.activate(focusedTarget(self.focus.index));
    }

    fn activate(self: *App, target: FocusTarget) void {
        switch (target) {
            .ip, .mask, .gateway, .dns, .apply => self.apply(false),
            .ok => self.apply(true),
            .cancel => self.should_exit = true,
            .defaults => self.loadDefaults(),
            .test_button => self.testGateway(),
        }
    }

    fn apply(self: *App, close_on_success: bool) void {
        var request: r4os.abi.NetConfigRequest = .{};
        if (!self.buildRequest(&request)) return;
        const result = self.ctx.net.netConfigSet(&request);
        if (result == r4os.abi.net_config_ok) {
            self.reloadSnapshot();
            self.setStatus("Saved and applied live.");
            if (close_on_success) self.should_exit = true;
            return;
        }
        if (result == r4os.abi.net_config_no_adapter) {
            self.reloadSnapshot();
            self.setStatus("Saved. No network adapter for live application.");
            self.setDialog(.warning, "Network", "Values saved, but no adapter is active.");
            self.dialog_open = true;
            return;
        }
        self.setStatus("Save failed.");
        self.setDialog(.failure, "Network", self.ctx.net.netConfigResultName(result));
        self.dialog_open = true;
    }

    fn loadDefaults(self: *App) void {
        self.ip.set("10.0.2.15");
        self.mask.set("255.255.255.0");
        self.gateway.set("10.0.2.2");
        self.dns.set("10.0.2.3");
        self.setStatus("QEMU defaults entered, not saved yet.");
    }

    fn testGateway(self: *App) void {
        var request: r4os.abi.NetConfigRequest = .{};
        if (!self.buildRequest(&request)) return;
        const gateway_ip = parseIpv4(self.gateway.value()) orelse return;
        var payload_buf: [32]u8 = .{0} ** 32;
        const payload = buildEchoRequest(payload_buf[0..], TEST_IDENT, TEST_SEQ) orelse {
            self.setStatus("Test could not build ICMP packet.");
            return;
        };
        const result = self.ctx.net.netIpv4Send(gateway_ip[0], gateway_ip[1], gateway_ip[2], gateway_ip[3], ICMP_PROTOCOL, payload);
        if (result == r4os.abi.net_tx_ok) {
            self.setStatus("Test: ICMP echo sent to the gateway.");
            self.setDialog(.info, "Network test", "ICMP echo was sent. Test the reply with PING.");
        } else {
            self.setStatus("Test failed.");
            self.setDialog(.warning, "Network test", self.ctx.net.netTxResultName(result));
        }
        self.dialog_open = true;
    }

    fn buildRequest(self: *App, request: *r4os.abi.NetConfigRequest) bool {
        const ip_value = parseIpv4(self.ip.value()) orelse return self.formError("Invalid IPv4 address.");
        const mask_value = parseIpv4(self.mask.value()) orelse return self.formError("Invalid netmask.");
        if (!validNetmask(mask_value)) return self.formError("Netmask must be contiguous.");
        _ = parseIpv4(self.gateway.value()) orelse return self.formError("Invalid gateway.");
        if (self.dns.value().len > 0) _ = parseIpv4(self.dns.value()) orelse return self.formError("Invalid DNS server.");
        _ = ip_value;
        request.* = .{};
        copyFixed(request.local_ip[0..], self.ip.value());
        copyFixed(request.netmask[0..], self.mask.value());
        copyFixed(request.gateway_ip[0..], self.gateway.value());
        copyFixed(request.dns_ip[0..], self.dns.value());
        request.flags = r4os.abi.net_config_flag_write_persistent | r4os.abi.net_config_flag_apply_live;
        return true;
    }

    fn formError(self: *App, message: []const u8) bool {
        self.setStatus(message);
        self.setDialog(.failure, "Input", message);
        self.dialog_open = true;
        return false;
    }

    fn setFocus(self: *App, target: FocusTarget) bool {
        _ = self.focus.set(focus_items[0..], focusIndex(target));
        self.syncFocus();
        self.render();
        return true;
    }

    fn syncFocus(self: *App) void {
        self.ip.focused = self.hasFocus(.ip);
        self.mask.focused = self.hasFocus(.mask);
        self.gateway.focused = self.hasFocus(.gateway);
        self.dns.focused = self.hasFocus(.dns);
    }

    fn focusedField(self: *App) ?*r4os.gui.TextField(16) {
        return switch (focusedTarget(self.focus.index)) {
            .ip => &self.ip,
            .mask => &self.mask,
            .gateway => &self.gateway,
            .dns => &self.dns,
            else => null,
        };
    }

    fn hasFocus(self: *const App, target: FocusTarget) bool {
        return self.focus.index == focusIndex(target);
    }

    fn setStatus(self: *App, value: []const u8) void {
        setZ(self.status[0..], value);
    }

    fn setDialog(self: *App, kind: r4os.gui.MessageKind, title: []const u8, message: []const u8) void {
        self.dialog_kind = kind;
        setZ(self.dialog_title[0..], title);
        setZ(self.dialog_message[0..], message);
    }

    fn messageDialog(self: *const App) r4os.gui.MessageDialog {
        return .{
            .rect = self.dialogRect(),
            .title = spanZ(self.dialog_title[0..]),
            .message = spanZ(self.dialog_message[0..]),
            .kind = self.dialog_kind,
        };
    }

    fn adapterRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 12, .y = 10, .w = self.w - 24, .h = 84 };
    }

    fn ipv4Rect(self: *const App) r4os.gui.Rect {
        return .{ .x = 12, .y = 104, .w = self.w - 24, .h = @max(126, self.h - 180) };
    }

    fn fieldX(self: *const App) i32 {
        _ = self;
        return 128;
    }

    fn fieldW(self: *const App) i32 {
        return @max(150, self.w - self.fieldX() - 28);
    }

    fn ipRect(self: *const App) r4os.gui.Rect {
        return .{ .x = self.fieldX(), .y = 132, .w = self.fieldW(), .h = 22 };
    }

    fn maskRect(self: *const App) r4os.gui.Rect {
        return .{ .x = self.fieldX(), .y = 160, .w = self.fieldW(), .h = 22 };
    }

    fn gatewayRect(self: *const App) r4os.gui.Rect {
        return .{ .x = self.fieldX(), .y = 188, .w = self.fieldW(), .h = 22 };
    }

    fn dnsRect(self: *const App) r4os.gui.Rect {
        return .{ .x = self.fieldX(), .y = 216, .w = self.fieldW(), .h = 22 };
    }

    fn buttonY(self: *const App) i32 {
        return self.h - 48;
    }

    fn defaultsRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 12, .y = self.buttonY(), .w = 76, .h = 24 };
    }

    fn testRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 96, .y = self.buttonY(), .w = 70, .h = 24 };
    }

    fn applyRect(self: *const App) r4os.gui.Rect {
        return .{ .x = @max(172, self.w - 250), .y = self.buttonY(), .w = 82, .h = 24 };
    }

    fn okRect(self: *const App) r4os.gui.Rect {
        return .{ .x = self.w - 160, .y = self.buttonY(), .w = 64, .h = 24 };
    }

    fn cancelRect(self: *const App) r4os.gui.Rect {
        return .{ .x = self.w - 88, .y = self.buttonY(), .w = 76, .h = 24 };
    }

    fn statusRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 0, .y = self.h - 18, .w = self.w, .h = 18 };
    }

    fn dialogRect(self: *const App) r4os.gui.Rect {
        return r4os.gui.centeredRect(.{ .x = 0, .y = 0, .w = self.w, .h = self.h }, @min(260, self.w - 24), 100);
    }
};

fn parseIpv4(value: []const u8) ?[4]u8 {
    var out: [4]u8 = .{0} ** 4;
    var part: usize = 0;
    var accum: u16 = 0;
    var digits: usize = 0;
    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const ch = value[index];
        if (ch >= '0' and ch <= '9') {
            accum = accum * 10 + @as(u16, ch - '0');
            if (accum > 255) return null;
            digits += 1;
            if (digits > 3) return null;
        } else if (ch == '.') {
            if (digits == 0 or part >= 3) return null;
            out[part] = @intCast(accum);
            part += 1;
            accum = 0;
            digits = 0;
        } else {
            return null;
        }
    }
    if (digits == 0 or part != 3) return null;
    out[part] = @intCast(accum);
    return out;
}

fn validNetmask(mask: [4]u8) bool {
    const value = (@as(u32, mask[0]) << 24) | (@as(u32, mask[1]) << 16) | (@as(u32, mask[2]) << 8) | mask[3];
    if (value == 0) return false;
    var seen_zero = false;
    var bit: u5 = 31;
    while (true) {
        const set = ((value >> bit) & 1) != 0;
        if (!set) seen_zero = true else if (seen_zero) return false;
        if (bit == 0) break;
        bit -= 1;
    }
    return true;
}

fn buildEchoRequest(out: []u8, ident: u16, seq: u16) ?[]const u8 {
    const data = "R4OSNETCFG";
    const len = 8 + data.len;
    if (out.len < len) return null;
    @memset(out[0..len], 0);
    out[0] = ICMP_ECHO_REQUEST;
    writeBe16(out, 4, ident);
    writeBe16(out, 6, seq);
    var i: usize = 0;
    while (i < data.len) : (i += 1) out[8 + i] = data[i];
    writeBe16(out, 2, checksum(out[0..len]));
    return out[0..len];
}

fn checksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var index: usize = 0;
    while (index + 1 < data.len) : (index += 2) {
        sum += (@as(u32, data[index]) << 8) | data[index + 1];
    }
    if (index < data.len) sum += @as(u32, data[index]) << 8;
    while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
    return @intCast(~sum & 0xFFFF);
}

fn writeBe16(buf: []u8, offset: usize, value: u16) void {
    buf[offset] = @intCast(value >> 8);
    buf[offset + 1] = @intCast(value & 0xFF);
}

fn ipText(out: []u8, ip: [4]u8) []const u8 {
    @memset(out, 0);
    appendByte(out, ip[0]);
    appendZ(out, ".");
    appendByte(out, ip[1]);
    appendZ(out, ".");
    appendByte(out, ip[2]);
    appendZ(out, ".");
    appendByte(out, ip[3]);
    return spanZ(out);
}

fn appendByte(out: []u8, value: u8) void {
    if (value >= 100) appendChar(out, '0' + value / 100);
    if (value >= 10) appendChar(out, '0' + (value / 10) % 10);
    appendChar(out, '0' + value % 10);
}

fn appendChar(out: []u8, ch: u8) void {
    const len = zLen(out);
    if (len + 1 >= out.len) return;
    out[len] = ch;
    out[len + 1] = 0;
}

fn copyFixed(out: []u8, text: []const u8) void {
    @memset(out, 0);
    if (out.len == 0) return;
    const count = @min(text.len, out.len - 1);
    if (count > 0) @memcpy(out[0..count], text[0..count]);
}

fn spanZ(buf: []const u8) []const u8 {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) : (len += 1) {}
    return buf[0..len];
}

fn zLen(buf: []const u8) usize {
    return spanZ(buf).len;
}

fn setZ(out: []u8, value: []const u8) void {
    @memset(out, 0);
    if (out.len == 0) return;
    const count = @min(value.len, out.len - 1);
    if (count > 0) @memcpy(out[0..count], value[0..count]);
    out[count] = 0;
}

fn appendZ(out: []u8, value: []const u8) void {
    var len = zLen(out);
    if (len >= out.len) return;
    const count = @min(value.len, out.len - len - 1);
    if (count > 0) @memcpy(out[len .. len + count], value[0..count]);
    len += count;
    out[len] = 0;
}

fn clampI32(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}

fn focusIndex(target: FocusTarget) usize {
    return @intFromEnum(target);
}

fn focusedTarget(index: usize) FocusTarget {
    if (index >= focus_items.len) return .ip;
    return @enumFromInt(index);
}
