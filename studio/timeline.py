"""Narration-driven timing: word lookups and named time expressions from project.yaml.

Every visual event in a reel should hang off a spoken word (or a beat), never a hand-typed second, so a new
voice take re-times the whole video by itself.

    tl = Timeline(project_dir)                    # loads voice/vo_words.json, shifted by vo_offset
    tl.word(7, "walk")                            # start of the first "walk" in line 7 (video time)
    tl.span(3)                                    # (start, end) of line 3
    T = tl.resolve(cfg["times"])                  # named times, see `expr()` for the syntax
"""
import json, os

from .common import load_cfg

_strip = lambda s: s.strip("?.,!…:;\"'").lower()


class Timeline:
    def __init__(self, project_dir, cfg=None):
        self.cfg = cfg or load_cfg(project_dir)
        self.vo_offset = self.cfg.get("vo_offset", 0.5)
        vd = os.path.join(project_dir, "voice")
        self.words = [dict(q, s=q["s"] + self.vo_offset, e=q["e"] + self.vo_offset)
                      for q in json.load(open(os.path.join(vd, "vo_words.json")))]
        self.lines = json.load(open(os.path.join(vd, "vo_lines.json")))
        end = os.path.join(vd, "end_line.json")
        self.ending = json.load(open(end)) if os.path.exists(end) else None
        self.beats, self.music_start, self.T = [], 0.0, {}

    # ------------------------------------------------------------ lookups
    def word(self, line, text, nth=0):
        hits = [w["s"] for w in self.words if w["line"] == line and _strip(w["w"]) == text.lower()]
        if len(hits) <= nth: raise KeyError(f"word {text!r} (#{nth}) not found in line {line}: {self.lines[line]!r}")
        return hits[nth]

    def word_end(self, line, text, nth=0):
        hits = [w["e"] for w in self.words if w["line"] == line and _strip(w["w"]) == text.lower()]
        return hits[nth]

    def span(self, line):
        ws = [w for w in self.words if w["line"] == line]
        return ws[0]["s"], ws[-1]["e"]

    def line_words(self, line): return [w for w in self.words if w["line"] == line]

    # ------------------------------------------------------------ music
    def use_music(self, beats, music_start):
        """beats: track-time beat list; music_start: track time playing at video t=0."""
        self.beats, self.music_start = beats, music_start

    def snap(self, t, window=None):
        cands = [b - self.music_start for b in self.beats]
        if window: cands = [c for c in cands if abs(c - t) <= window]
        return min(cands, key=lambda b: abs(b - t)) if cands else t

    # ------------------------------------------------------------ expressions
    def expr(self, e):
        """A time, written in project.yaml as any of:
            12.5                         seconds (video time)
            DROP                         a name defined earlier in `times:` (or "END" = video duration)
            {word: [7, walk]}            start of a word: [line, word] or [line, word, nth]
            {word_end: [7, walk]}        end of a word
            {line_start: 3} / {line_end: 3}
            {gap: [0, 1]}                middle of the pause between line 0 and line 1  (beat-snapped)
            {before: [1, everyone]}      just before a word (-0.12 s)                  (beat-snapped)
            {music: 19.975}              a moment of the music track (e.g. a drop) in video time
          plus optional keys: add: -0.3 (offset seconds), snap: true/false (to the nearest beat)."""
        if isinstance(e, (int, float)): return float(e)
        if isinstance(e, str):
            if e in self.T: return self.T[e]
            raise KeyError(f"time {e!r} is not defined (yet) in `times:`")
        e = dict(e); add = e.pop("add", 0.0); snap = e.pop("snap", None)
        (k, v), = e.items()
        if k == "word": t = self.word(*v)
        elif k == "word_end": t = self.word_end(*v)
        elif k == "line_start": t = self.span(v)[0]
        elif k == "line_end": t = self.span(v)[1]
        elif k == "gap": t = (self.span(v[0])[1] + self.span(v[1])[0]) / 2; snap = True if snap is None else snap
        elif k == "before": t = self.word(*v) - 0.12; snap = True if snap is None else snap
        elif k == "music": t = v - self.music_start
        elif k == "at": t = self.expr(v)
        else: raise KeyError(f"unknown time expression {k!r}")
        t += add
        return self.snap(t) if snap and self.beats else t

    def resolve(self, times):
        """Evaluate the ordered `times:` mapping (later names may use earlier ones)."""
        for name, e in (times or {}).items():
            self.T[name] = self.expr(e)
        return self.T
