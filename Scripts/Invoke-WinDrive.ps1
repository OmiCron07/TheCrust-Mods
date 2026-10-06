<#
.SYNOPSIS
    Sends a batch of mouse/keyboard commands to The Crust window, one reply line per command.
.DESCRIPTION
    Last-resort UI driver for in-game verification; prefer Invoke-DevBridge.ps1 for state and actions.
    Coordinates are CLIENT coordinates in physical pixels, i.e. pixels of a Get-GameScreenshot.ps1 PNG.
    Adapted and audited from universal-modder um/ps1/WinDrive.ps1 (MIT).

    Safety guards:
      - input is sent only while the game is the foreground window (or nothing is and the cursor is over it);
      - refuses to start if the user touched mouse/keyboard less than -MinIdleSeconds ago;
      - aborts the batch as soon as real user input is detected between commands;
      - focus never clicks inside the game: it clicks the title bar or fails;
      - the batch stops at the first failing command.

    Commands:
      focus                      bring the window to the foreground            -> ok | fail
      rect                       client area in screen coords                   -> x y w h | none
      fg                         name of the foreground process
      idle                       seconds since the last input on this machine
      size <w> <h>               resize so the CLIENT area is w x h (windowed mode)
      wait <ms>                  sleep
      move <x> <y>               cursor to client coords
      click <x> <y> [right]      click (left by default)
      mdown <x> <y> [right] / mup [right]
      drag <x0> <y0> <x1> <y1>   left-drag
      rel <dx> <dy>              relative mouse move (raw-input cameras)
      key <vk> [tap|down|up]     virtual-key, hex (0x1B) or decimal
      hold <vk> <ms>             hold a key
      type <text>                unicode text
      wheel <delta>              mouse wheel (120 = one notch up, -120 down)
      scanmode on|off            hardware scan codes (games that ignore VK-only events)
    VK: Esc 0x1B, Enter 0x0D, Space 0x20, W/A/S/D 0x57/0x41/0x53/0x44, Shift 0x10, Ctrl 0x11, F1 0x70.
.EXAMPLE
    .\Invoke-WinDrive.ps1 "focus" "click 1280 720" "wait 500" "key 0x1B"
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Commands,
    [string]$Proc = "TheCrust-Win64-Shipping",
    [double]$MinIdleSeconds = 5
)

$ErrorActionPreference = "Stop"

$src = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class WinDrive
{
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct U { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public U u; }
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint size, time; }

    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO i);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);

    static string proc;
    static bool scanMode = false;
    static uint lastOwnInput = 0;   // tick of our last injected input; 0 = none yet

    static IntPtr Window()
    {
        foreach (var p in Process.GetProcessesByName(proc))
            if (p.MainWindowHandle != IntPtr.Zero) return p.MainWindowHandle;
        return IntPtr.Zero;
    }

    static string ProcName(IntPtr h)
    {
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        try { return Process.GetProcessById((int)pid).ProcessName; } catch { return "?"; }
    }

    static bool IsForeground()
    {
        var fg = GetForegroundWindow();
        return fg != IntPtr.Zero && ProcName(fg).Equals(proc, StringComparison.OrdinalIgnoreCase);
    }

    static uint LastInputTick()
    {
        var li = new LASTINPUTINFO(); li.size = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref li);
        return li.time;
    }

    public static double IdleSeconds() { return unchecked((uint)Environment.TickCount - LastInputTick()) / 1000.0; }

    // Real user input = an input event newer than our own last injection (+ margin for event latency).
    static void GuardUser()
    {
        if (lastOwnInput != 0 && unchecked((int)(LastInputTick() - lastOwnInput)) > 250)
            throw new InvalidOperationException("user input detected, batch aborted");
    }

    static void Stamp() { lastOwnInput = (uint)Environment.TickCount; }

    static INPUT Mouse(uint flags, uint data, int dx, int dy)
    {
        var i = new INPUT(); i.type = 0; i.u.mi.flags = flags; i.u.mi.data = data; i.u.mi.dx = dx; i.u.mi.dy = dy; return i;
    }

    static INPUT Key(ushort vk, bool up)
    {
        var i = new INPUT(); i.type = 1;
        ushort sc = (ushort)MapVirtualKey(vk, 0);
        bool ext = vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28 || vk == 0x2D || vk == 0x2E || vk == 0x24 || vk == 0x23 || vk == 0x21 || vk == 0x22 || vk == 0xA3 || vk == 0xA5;
        if (scanMode) { i.u.ki.vk = 0; i.u.ki.scan = sc; i.u.ki.flags = 0x0008u | (up ? 2u : 0u) | (ext ? 1u : 0u); }
        else { i.u.ki.vk = vk; i.u.ki.scan = sc; i.u.ki.flags = (up ? 2u : 0u) | (ext ? 1u : 0u); }
        return i;
    }

    // Safe if the game is the foreground window, or if nothing is (windowed games can drop the
    // foreground on clicks) and the cursor is over the game - then input can only reach the game.
    static bool Safe()
    {
        if (IsForeground()) return true;
        if (GetForegroundWindow() != IntPtr.Zero) return false;
        POINT p; GetCursorPos(out p);
        var under = WindowFromPoint(p);
        var h = Window();
        return under == h || GetAncestor(under, 2) == GetAncestor(h, 2);
    }

    static void Send(params INPUT[] i)
    {
        GuardUser();
        if (!Safe()) throw new InvalidOperationException("game is not in the foreground (foreground: " + ProcName(GetForegroundWindow()) + ")");
        SendInput((uint)i.Length, i, Marshal.SizeOf(typeof(INPUT)));
        Stamp();
    }

    static void MoveTo(int x, int y)
    {
        GuardUser();
        if (!Safe()) throw new InvalidOperationException("game is not in the foreground, cursor not moved");
        var p = new POINT(); p.X = x; p.Y = y;
        ClientToScreen(Window(), ref p);
        SetCursorPos(p.X, p.Y);
        Stamp();
    }

    static bool Focus()
    {
        var h = Window();
        if (h == IntPtr.Zero) return false;
        if (IsForeground()) return true;
        uint dummy;
        uint target = GetWindowThreadProcessId(h, out dummy), me = GetCurrentThreadId();
        AttachThreadInput(me, target, true);
        ShowWindow(h, 9);
        SetForegroundWindow(h);
        AttachThreadInput(me, target, false);
        Thread.Sleep(300);
        if (IsForeground()) return true;
        // Foreground lock: click the title bar (never the game's client area); borderless windows -> fail.
        RECT wr; GetWindowRect(h, out wr);
        var c = new POINT(); ClientToScreen(h, ref c);
        if (c.Y - wr.T < 8) return false;
        var p = new POINT(); p.X = (wr.L + wr.R) / 2; p.Y = (wr.T + c.Y) / 2;
        var under = WindowFromPoint(p);
        if (under != h && GetAncestor(under, 2) != GetAncestor(h, 2)) return false;
        GuardUser();
        SetCursorPos(p.X, p.Y);
        SendInput(1, new INPUT[] { Mouse(2u, 0, 0, 0) }, Marshal.SizeOf(typeof(INPUT)));
        SendInput(1, new INPUT[] { Mouse(4u, 0, 0, 0) }, Marshal.SizeOf(typeof(INPUT)));
        Stamp();
        Thread.Sleep(300);
        return IsForeground();
    }

    static ushort Vk(string s) { return s.StartsWith("0x") ? Convert.ToUInt16(s, 16) : ushort.Parse(s); }

    static string Do(string line)
    {
        var a = line.Trim().Split(new char[] { ' ' }, 2);
        var rest = a.Length > 1 ? a[1] : "";
        var n = rest.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        switch (a[0])
        {
            case "focus": return Focus() ? "ok" : "fail";
            case "fg": return ProcName(GetForegroundWindow());
            case "idle": return IdleSeconds().ToString("F1", System.Globalization.CultureInfo.InvariantCulture);
            case "wait": Thread.Sleep(int.Parse(n[0])); return "ok";
            case "rect":
            {
                var h = Window();
                if (h == IntPtr.Zero) return "none";
                RECT r; GetClientRect(h, out r);
                var p = new POINT(); ClientToScreen(h, ref p);
                return p.X + " " + p.Y + " " + (r.R - r.L) + " " + (r.B - r.T);
            }
            case "size":
            {
                var h = Window();
                if (h == IntPtr.Zero) return "fail";
                RECT wr, cr; GetWindowRect(h, out wr); GetClientRect(h, out cr);
                int bw = (wr.R - wr.L) - (cr.R - cr.L), bh = (wr.B - wr.T) - (cr.B - cr.T);
                SetWindowPos(h, IntPtr.Zero, 0, 0, int.Parse(n[0]) + bw, int.Parse(n[1]) + bh, 0x0002 | 0x0004);
                return "ok";
            }
            case "move": MoveTo(int.Parse(n[0]), int.Parse(n[1])); return "ok";
            case "click":
            {
                MoveTo(int.Parse(n[0]), int.Parse(n[1]));
                Thread.Sleep(40);
                bool right = n.Length > 2 && n[2] == "right";
                Send(Mouse(right ? 8u : 2u, 0, 0, 0)); Thread.Sleep(60); Send(Mouse(right ? 16u : 4u, 0, 0, 0));
                return "ok";
            }
            case "mdown": { MoveTo(int.Parse(n[0]), int.Parse(n[1])); Thread.Sleep(30); Send(Mouse(n.Length > 2 && n[2] == "right" ? 8u : 2u, 0, 0, 0)); return "ok"; }
            case "mup": { Send(Mouse(n.Length > 0 && n[0] == "right" ? 16u : 4u, 0, 0, 0)); return "ok"; }
            case "rel": { Send(Mouse(0x0001, 0, int.Parse(n[0]), int.Parse(n[1]))); return "ok"; }
            case "drag":
            {
                int x0 = int.Parse(n[0]), y0 = int.Parse(n[1]), x1 = int.Parse(n[2]), y1 = int.Parse(n[3]);
                MoveTo(x0, y0); Thread.Sleep(40);
                Send(Mouse(2u, 0, 0, 0)); Thread.Sleep(80);
                try { for (int k = 1; k <= 10; k++) { MoveTo(x0 + (x1 - x0) * k / 10, y0 + (y1 - y0) * k / 10); Thread.Sleep(20); } }
                finally { SendInput(1, new INPUT[] { Mouse(4u, 0, 0, 0) }, Marshal.SizeOf(typeof(INPUT))); Stamp(); }
                return "ok";
            }
            case "key":
            {
                var vk = Vk(n[0]);
                string mode = n.Length > 1 ? n[1] : "tap";
                if (mode != "up") Send(Key(vk, false));
                if (mode == "tap") Thread.Sleep(50);
                if (mode != "down") Send(Key(vk, true));
                return "ok";
            }
            case "hold": { var vk = Vk(n[0]); Send(Key(vk, false)); Thread.Sleep(int.Parse(n[1])); Send(Key(vk, true)); return "ok"; }
            case "scanmode": scanMode = n.Length > 0 && n[0] == "on"; return "ok";
            case "type":
                foreach (char c in rest)
                {
                    var d = new INPUT(); d.type = 1; d.u.ki.scan = c; d.u.ki.flags = 4;
                    var u = new INPUT(); u.type = 1; u.u.ki.scan = c; u.u.ki.flags = 4 | 2;
                    Send(d, u);
                    Thread.Sleep(10);
                }
                return "ok";
            case "wheel": Send(Mouse(0x0800, unchecked((uint)int.Parse(n[0])), 0, 0)); return "ok";
            default: return "error unknown command " + a[0];
        }
    }

    // Returns false when the batch stopped early.
    public static bool Run(string p, string[] commands)
    {
        SetProcessDpiAwarenessContext(new IntPtr(-4)); // per-monitor v2: client coords = screenshot pixels
        proc = p.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? p.Substring(0, p.Length - 4) : p;
        if (Window() == IntPtr.Zero) { Console.WriteLine("error no window for process " + proc); return false; }
        foreach (var line in commands)
        {
            if (line.Trim().Length == 0) continue;
            string reply;
            try { reply = Do(line); } catch (Exception e) { reply = "error " + e.Message; }
            Console.WriteLine(line + " -> " + reply);
            if (reply.StartsWith("error") || reply == "fail") return false;
        }
        return true;
    }
}
"@

if (-not ("WinDrive" -as [type])) { Add-Type -TypeDefinition $src -Language CSharp }

$idle = [WinDrive]::IdleSeconds()
$inputCommands = $Commands | ForEach-Object { ($_ -split ' ')[0] } | Where-Object { $_ -notin "rect", "fg", "idle", "wait", "size" }
if ($inputCommands -and $idle -lt $MinIdleSeconds) {
    throw "User active $([math]::Round($idle, 1))s ago (< $MinIdleSeconds s). Ask the user to step away, or lower -MinIdleSeconds."
}
if (-not [WinDrive]::Run($Proc, $Commands)) { exit 1 }
