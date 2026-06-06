#!/usr/bin/env python3
"""
ShowRunner - minimal live concert playback for Lionel Yu's Belgium concert.

WHAT IT DOES
  Per piece, on one keypress (SPACE = GO):
    * If the piece has audio: plays Backing.wav to device outputs 1-2 (FOH) and
      Click.wav to outputs 3-4 (in-ears), SAMPLE-LOCKED (one interleaved buffer).
    * Shows the piece's TitleCard.png full-screen on the audience display,
      fading 0->100% over FADE_SECONDS. Next GO / C clears it (fade to black).

WHY PYTHON  sounddevice -> PortAudio -> CoreAudio: same audio path as native apps.
  Sample-lock is guaranteed because backing+click are mixed into ONE buffer and
  streamed off one clock. You can edit this file in any text editor at the venue.

DEPENDENCIES (install once):
    pip3 install sounddevice soundfile numpy pillow
    # PortAudio (the C lib sounddevice needs):
    brew install portaudio
  Title cards use Tkinter (ships with macOS Python). No other GUI deps.

RUN:
    python3 showrunner.py                # normal: control window + audience fullscreen
    python3 showrunner.py --windowed     # title card in a window (one-display testing)
    python3 showrunner.py --selftest     # check files + audio device, no GUI
    python3 showrunner.py --list-devices # print audio devices and exit
    python3 showrunner.py --list-displays# print displays and exit

CONFIG: edit showrunner.json (running order, audio device name, fade time,
        which display is the audience output). No recompiling.

KEYS (in the control window):
    SPACE / RETURN  GO  - fire the selected piece (card fade-in; audio if any)
    DOWN / UP           - move selection (does NOT fire)
    C                   - clear the card (fade to black), keep audio
    ESC / S             - PANIC: stop audio + fade card to black
    Q                   - quit
"""

import sys, os, json, time, threading, traceback, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "showrunner.json")
LOG_PATH = os.path.join(HERE, "showrunner.log")

# ----- defaults if no config present -----
DEFAULTS = {
    "showRoot": os.path.dirname(HERE),  # the "Belgium Concert Program" folder
    "audioDeviceName": "Audient",       # loose match
    "fadeSeconds": 1.0,
    "audienceDisplayIndex": 1,          # 0 = main, 1 = second display
    "backingChannels": [1, 2],          # 1-based device output channels (FOH)
    "clickChannels": [3, 4],            # 1-based device output channels (ears)
    "pieces": []
}


def log(msg):
    line = f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {msg}"
    print(line)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            cfg = json.load(f)
        for k, v in DEFAULTS.items():
            cfg.setdefault(k, v)
        return cfg
    log("No showrunner.json found; using built-in defaults (no pieces).")
    return dict(DEFAULTS)


# =====================================================================
# AUDIO ENGINE
# =====================================================================
class AudioEngine:
    """Plays a pre-mixed multi-channel buffer to a chosen device. Sample-locked
    because backing+click live in one buffer streamed off one clock."""

    def __init__(self, device_name, backing_ch, click_ch):
        self.device_name = device_name
        self.backing_ch = backing_ch      # 1-based
        self.click_ch = click_ch          # 1-based
        self.sd = None
        self.sf = None
        self.np = None
        self.device_index = None
        self.device_max_out = 0
        self.stream = None
        self._buf = None
        self._pos = 0
        self._lock = threading.Lock()
        self._loaded = {}                 # folder -> (buffer, samplerate)

    def available(self):
        try:
            import sounddevice as sd
            import soundfile as sf
            import numpy as np
            self.sd, self.sf, self.np = sd, sf, np
            return True
        except Exception as e:
            log(f"AUDIO unavailable: {e}")
            return False

    def find_device(self):
        sd = self.sd
        want = (self.device_name or "").lower()
        best = None
        for i, d in enumerate(sd.query_devices()):
            if d["max_output_channels"] >= max(self.backing_ch + self.click_ch):
                if want and want in d["name"].lower():
                    best = (i, d)
                    break
        if best is None:
            # fallback: first device with enough output channels
            for i, d in enumerate(sd.query_devices()):
                if d["max_output_channels"] >= max(self.backing_ch + self.click_ch):
                    best = (i, d); break
        if best is None:
            log("AUDIO: no device with >=4 output channels found.")
            return False
        self.device_index, dev = best
        self.device_max_out = dev["max_output_channels"]
        log(f"AUDIO device: [{self.device_index}] {dev['name']} "
            f"({self.device_max_out} out ch)")
        return True

    def list_devices(self):
        import sounddevice as sd
        for i, d in enumerate(sd.query_devices()):
            print(f"[{i}] {d['name']}  out={d['max_output_channels']} "
                  f"in={d['max_input_channels']} sr={int(d['default_samplerate'])}")

    def build_buffer(self, backing_path, click_path):
        """Return (interleaved_float32 [n, device_max_out], samplerate)."""
        np, sf = self.np, self.sf
        b, sr_b = sf.read(backing_path, dtype="float32", always_2d=True)
        if click_path and os.path.exists(click_path):
            c, sr_c = sf.read(click_path, dtype="float32", always_2d=True)
        else:
            c, sr_c = np.zeros_like(b), sr_b
        if sr_b != sr_c:
            raise ValueError(f"sample rate mismatch {sr_b} vs {sr_c}")
        n = max(len(b), len(c))
        if len(b) < n: b = np.pad(b, ((0, n - len(b)), (0, 0)))
        if len(c) < n: c = np.pad(c, ((0, n - len(c)), (0, 0)))
        out = np.zeros((n, self.device_max_out), dtype="float32")
        # map: backing L/R -> backing_ch, click L/R -> click_ch (1-based -> 0-based)
        out[:, self.backing_ch[0] - 1] = b[:, 0]
        out[:, self.backing_ch[1] - 1] = b[:, 1] if b.shape[1] > 1 else b[:, 0]
        out[:, self.click_ch[0] - 1] = c[:, 0]
        out[:, self.click_ch[1] - 1] = c[:, 1] if c.shape[1] > 1 else c[:, 0]
        return out, sr_b

    def preload(self, folder, backing_path, click_path):
        try:
            self._loaded[folder] = self.build_buffer(backing_path, click_path)
            return True
        except Exception as e:
            log(f"AUDIO preload failed for {folder}: {e}")
            return False

    def _callback(self, outdata, frames, time_info, status):
        np = self.np
        if status:
            log(f"AUDIO status: {status}")
        with self._lock:
            if self._buf is None:
                outdata.fill(0); return
            end = self._pos + frames
            chunk = self._buf[self._pos:end]
            if len(chunk) < frames:
                outdata[:len(chunk)] = chunk
                outdata[len(chunk):] = 0
                self._buf = None; self._pos = 0
                raise self.sd.CallbackStop()
            else:
                outdata[:] = chunk
                self._pos = end

    def play(self, folder, backing_path, click_path, samplerate_hint=None):
        self.stop()
        if folder not in self._loaded:
            if not self.preload(folder, backing_path, click_path):
                return False
        buf, sr = self._loaded[folder]
        with self._lock:
            self._buf = buf; self._pos = 0
        try:
            self.stream = self.sd.OutputStream(
                samplerate=sr,
                device=self.device_index,
                channels=self.device_max_out,
                dtype="float32",
                callback=self._callback,
                finished_callback=lambda: log(f"AUDIO finished: {folder}")
            )
            self.stream.start()
            log(f"AUDIO play: {folder}  ({len(buf)/sr:.1f}s, sr={sr})")
            return True
        except Exception as e:
            log(f"AUDIO play error: {e}")
            return False

    def stop(self):
        try:
            if self.stream is not None:
                self.stream.abort(); self.stream.close()
        except Exception:
            pass
        self.stream = None
        with self._lock:
            self._buf = None; self._pos = 0

    def elapsed(self):
        with self._lock:
            if self._buf is None or self.stream is None:
                return None
            return self._pos / self.stream.samplerate


# =====================================================================
# AUDIENCE DISPLAY (title cards) - Tkinter, GPU-free crossfade via PIL alpha
# =====================================================================
class TitleDisplay:
    def __init__(self, root_tk, display_index, fade_seconds, windowed=False):
        import tkinter as tk
        self.tk = tk
        self.fade = fade_seconds
        self.windowed = windowed
        self.win = tk.Toplevel(root_tk)
        self.win.configure(bg="black")
        self.win.title("ShowRunner Output")
        self._photo = None
        self._img_cache = {}     # path -> PIL.Image (sized to screen)
        self._fade_job = None

        # Geometry: place on the chosen display, fullscreen black.
        geo = self._display_geometry(display_index)
        if windowed or geo is None:
            self.win.geometry("960x540+80+80")
            self.sw, self.sh = 960, 540
        else:
            x, y, w, h = geo
            self.win.geometry(f"{w}x{h}+{x}+{y}")
            self.win.overrideredirect(True)     # borderless
            self.win.lift()
            self.sw, self.sh = w, h
        self.canvas = tk.Canvas(self.win, bg="black", highlightthickness=0,
                                width=self.sw, height=self.sh)
        self.canvas.pack(fill="both", expand=True)
        self._black()

    def _display_geometry(self, idx):
        """Best-effort multi-monitor geometry via AppKit; fall back to None."""
        try:
            from AppKit import NSScreen
            screens = NSScreen.screens()
            if idx < 0 or idx >= len(screens):
                idx = len(screens) - 1   # last screen if index out of range
            fr = screens[idx].frame()
            # Tkinter uses top-left origin; macOS uses bottom-left. Convert.
            main_h = screens[0].frame().size.height
            x = int(fr.origin.x)
            y = int(main_h - fr.origin.y - fr.size.height)
            return (x, y, int(fr.size.width), int(fr.size.height))
        except Exception as e:
            log(f"DISPLAY geometry fallback (no pyobjc?): {e}")
            return None

    def _black(self):
        self.canvas.delete("all")
        self.canvas.configure(bg="black")

    def _load_sized(self, path):
        from PIL import Image
        if path in self._img_cache:
            return self._img_cache[path]
        img = Image.open(path).convert("RGB")
        # letterbox into screen, preserve aspect
        iw, ih = img.size
        scale = min(self.sw / iw, self.sh / ih)
        nw, nh = int(iw * scale), int(ih * scale)
        img = img.resize((nw, nh), Image.LANCZOS)
        canvas_img = Image.new("RGB", (self.sw, self.sh), (0, 0, 0))
        canvas_img.paste(img, ((self.sw - nw) // 2, (self.sh - nh) // 2))
        self._img_cache[path] = canvas_img
        return canvas_img

    def show(self, path):
        """Fade the title card in from black."""
        from PIL import Image, ImageTk
        if self._fade_job:
            self.win.after_cancel(self._fade_job); self._fade_job = None
        if not path or not os.path.exists(path):
            log(f"DISPLAY missing image: {path}")
            self._black(); return
        target = self._load_sized(path)
        black = Image.new("RGB", (self.sw, self.sh), (0, 0, 0))
        steps = max(1, int(self.fade * 30))
        self.win.lift()

        def step(i):
            alpha = i / steps
            frame = Image.blend(black, target, alpha)
            self._photo = ImageTk.PhotoImage(frame)
            self.canvas.delete("all")
            self.canvas.create_image(self.sw // 2, self.sh // 2, image=self._photo)
            if i < steps:
                self._fade_job = self.win.after(int(1000 * self.fade / steps),
                                                lambda: step(i + 1))
            else:
                self._fade_job = None
        step(0)

    def clear(self):
        """Fade current card to black."""
        from PIL import Image, ImageTk
        if self._fade_job:
            self.win.after_cancel(self._fade_job); self._fade_job = None
        # capture whatever is shown by re-blending from last target isn't tracked;
        # simplest robust clear: quick fade of a copy of current photo to black.
        steps = max(1, int(self.fade * 30))
        # If nothing meaningful is shown, just go black.
        try:
            base = self._last_target
        except AttributeError:
            base = None
        if base is None:
            self._black(); return
        black = Image.new("RGB", (self.sw, self.sh), (0, 0, 0))

        def step(i):
            alpha = 1 - i / steps
            frame = Image.blend(black, base, alpha)
            self._photo = ImageTk.PhotoImage(frame)
            self.canvas.delete("all")
            self.canvas.create_image(self.sw // 2, self.sh // 2, image=self._photo)
            if i < steps:
                self._fade_job = self.win.after(int(1000 * self.fade / steps),
                                                lambda: step(i + 1))
            else:
                self._black(); self._fade_job = None
        step(0)


# =====================================================================
# APP / CONTROL WINDOW
# =====================================================================
class ShowRunner:
    def __init__(self, cfg, windowed=False):
        import tkinter as tk
        self.tk = tk
        self.cfg = cfg
        self.windowed = windowed
        self.pieces = cfg["pieces"]
        self.sel = 0
        self.root = tk.Tk()
        self.root.title("ShowRunner - Belgium Concert")
        self.root.configure(bg="#111")
        self.root.geometry("520x720+40+40")

        self.audio = AudioEngine(cfg["audioDeviceName"],
                                 cfg["backingChannels"], cfg["clickChannels"])
        self.audio_ok = self.audio.available() and self.audio.find_device()

        self.display = TitleDisplay(self.root, cfg["audienceDisplayIndex"],
                                    cfg["fadeSeconds"], windowed=windowed)

        self._build_ui()
        self._bind_keys()
        self._preload_all()
        self._tick()

    def _build_ui(self):
        tk = self.tk
        head = tk.Label(self.root, text="ShowRunner", fg="#d8bd6f", bg="#111",
                        font=("Helvetica", 22, "bold"))
        head.pack(pady=(12, 0))
        sub = "AUDIO OK" if self.audio_ok else "AUDIO NOT READY (see log / --selftest)"
        self.status = tk.Label(self.root, text=sub,
                               fg=("#8fdf8f" if self.audio_ok else "#f08a8a"),
                               bg="#111", font=("Helvetica", 11))
        self.status.pack()
        self.listbox = tk.Listbox(self.root, bg="#1b1b1b", fg="#eee",
                                  selectbackground="#33506f",
                                  font=("Helvetica", 15), activestyle="none",
                                  highlightthickness=0, height=22)
        self.listbox.pack(fill="both", expand=True, padx=12, pady=10)
        for p in self.pieces:
            mark = ""
            if p.get("hasAudio"):
                ok = self._files_present(p)
                mark = "  [audio OK]" if ok else "  [AUDIO MISSING]"
            self.listbox.insert("end", f"{p['order']:>2}  {p['title']}{mark}")
        self.listbox.selection_set(0)
        self.listbox.bind("<<ListboxSelect>>", self._on_select)

        self.now = tk.Label(self.root, text="", fg="#9fb6d0", bg="#111",
                            font=("Helvetica", 12))
        self.now.pack(pady=(0, 4))
        btns = tk.Frame(self.root, bg="#111"); btns.pack(pady=(0, 12))
        tk.Button(btns, text="GO  (Space)", command=self.go,
                  bg="#2a6", fg="white", font=("Helvetica", 14, "bold"),
                  width=12).pack(side="left", padx=6)
        tk.Button(btns, text="STOP / PANIC  (Esc)", command=self.panic,
                  bg="#a33", fg="white", font=("Helvetica", 14, "bold"),
                  width=16).pack(side="left", padx=6)

    def _bind_keys(self):
        r = self.root
        r.bind("<space>", lambda e: self.go())
        r.bind("<Return>", lambda e: self.go())
        r.bind("<Down>", lambda e: self.move(1))
        r.bind("<Up>", lambda e: self.move(-1))
        r.bind("c", lambda e: self.clear())
        r.bind("C", lambda e: self.clear())
        r.bind("<Escape>", lambda e: self.panic())
        r.bind("s", lambda e: self.panic())
        r.bind("S", lambda e: self.panic())
        r.bind("q", lambda e: self.quit())
        r.bind("Q", lambda e: self.quit())

    def _piece_dir(self, p):
        return os.path.join(self.cfg["showRoot"], p["folder"])

    def _files_present(self, p):
        d = self._piece_dir(p)
        b = os.path.join(d, p.get("backing") or "")
        c = os.path.join(d, p.get("click") or "")
        return os.path.exists(b) and os.path.exists(c)

    def _card_path(self, p):
        return os.path.join(self._piece_dir(p), p.get("titleCard", "TitleCard.png"))

    def _preload_all(self):
        if not self.audio_ok:
            return
        for p in self.pieces:
            if p.get("hasAudio") and self._files_present(p):
                d = self._piece_dir(p)
                self.audio.preload(p["folder"],
                                   os.path.join(d, p["backing"]),
                                   os.path.join(d, p["click"]))

    def _on_select(self, _e):
        sel = self.listbox.curselection()
        if sel:
            self.sel = sel[0]

    def move(self, delta):
        self.sel = max(0, min(len(self.pieces) - 1, self.sel + delta))
        self.listbox.selection_clear(0, "end")
        self.listbox.selection_set(self.sel)
        self.listbox.see(self.sel)

    def go(self):
        if not self.pieces:
            return
        p = self.pieces[self.sel]
        log(f"GO -> {p['order']} {p['title']}")
        # title card (track last target for clean clear)
        card = self._card_path(p)
        try:
            from PIL import Image
            self.display._last_target = self.display._load_sized(card) \
                if os.path.exists(card) else None
        except Exception:
            self.display._last_target = None
        self.display.show(card)
        # audio
        if p.get("hasAudio"):
            if not self.audio_ok:
                self.status.config(text="AUDIO NOT READY", fg="#f08a8a")
            elif self._files_present(p):
                d = self._piece_dir(p)
                self.audio.play(p["folder"],
                                os.path.join(d, p["backing"]),
                                os.path.join(d, p["click"]))
            else:
                log(f"GO: audio files missing for {p['title']}")

    def clear(self):
        self.display.clear()

    def panic(self):
        log("PANIC")
        self.audio.stop()
        self.display.clear()

    def quit(self):
        self.audio.stop()
        self.root.destroy()

    def _tick(self):
        el = self.audio.elapsed() if self.audio_ok else None
        if el is not None:
            m, s = divmod(int(el), 60)
            self.now.config(text=f"playing  {m:d}:{s:02d}")
        else:
            self.now.config(text="")
        self.root.after(250, self._tick)

    def run(self):
        self.root.mainloop()


# =====================================================================
# CLI
# =====================================================================
def selftest(cfg):
    print("=== ShowRunner self-test ===")
    eng = AudioEngine(cfg["audioDeviceName"], cfg["backingChannels"],
                      cfg["clickChannels"])
    if not eng.available():
        print("FAIL: sounddevice/soundfile/numpy not importable. "
              "pip3 install sounddevice soundfile numpy ; brew install portaudio")
        return 1
    if not eng.find_device():
        print("FAIL: no audio device with >=4 outputs. Plug in the Audient iD44.")
        eng.list_devices()
        return 1
    ok = True
    for p in cfg["pieces"]:
        if not p.get("hasAudio"):
            continue
        d = os.path.join(cfg["showRoot"], p["folder"])
        b = os.path.join(d, p.get("backing") or "")
        c = os.path.join(d, p.get("click") or "")
        if not (os.path.exists(b) and os.path.exists(c)):
            print(f"  MISSING audio: {p['title']}")
            ok = False; continue
        try:
            buf, sr = eng.build_buffer(b, c)
            dur = len(buf) / sr
            print(f"  OK  {p['title']:<28} {dur:6.1f}s sr={sr} "
                  f"backing->ch{cfg['backingChannels']} click->ch{cfg['clickChannels']}")
        except Exception as e:
            print(f"  FAIL {p['title']}: {e}"); ok = False
    # also check title cards
    for p in cfg["pieces"]:
        card = os.path.join(cfg["showRoot"], p["folder"],
                            p.get("titleCard", "TitleCard.png"))
        if not os.path.exists(card):
            print(f"  MISSING card: {p['title']}"); ok = False
    print("=== self-test:", "PASS" if ok else "PROBLEMS FOUND", "===")
    return 0 if ok else 1


def main():
    cfg = load_config()
    args = sys.argv[1:]
    if "--list-devices" in args:
        try:
            import sounddevice as sd
            for i, d in enumerate(sd.query_devices()):
                print(f"[{i}] {d['name']}  out={d['max_output_channels']}")
        except Exception as e:
            print("sounddevice not available:", e)
        return
    if "--list-displays" in args:
        try:
            from AppKit import NSScreen
            for i, s in enumerate(NSScreen.screens()):
                f = s.frame()
                print(f"[{i}] {int(f.size.width)}x{int(f.size.height)} "
                      f"at ({int(f.origin.x)},{int(f.origin.y)})")
        except Exception as e:
            print("pyobjc/AppKit not available (pip3 install pyobjc):", e)
        return
    if "--selftest" in args:
        sys.exit(selftest(cfg))
    windowed = "--windowed" in args
    try:
        app = ShowRunner(cfg, windowed=windowed)
        app.run()
    except Exception:
        log("FATAL:\n" + traceback.format_exc())
        raise


if __name__ == "__main__":
    main()
