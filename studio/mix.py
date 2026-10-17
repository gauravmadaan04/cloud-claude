"""Final mix + mux, format-agnostic.

    mix(out_wav, dur, voice_wav, music, music_start, sfx_wav=..., dips=[(t0, depth)])
    mux(video, audio, final)            # prints loudness, warns on clipping

Voice is cleaned (highpass, presence boost, compression), music is side-chain ducked under it, everything is
normalised to -14 LUFS then pushed +gain_db and brick-wall limited (reels play on phone speakers: louder wins).
"""
import os, subprocess

from .common import ROOT


def mix(out_wav, dur, voice_wav, music, music_start, sfx_wav=None, vo_offset=0.5, gain_db=7.0, limit=0.72,
        music_level=0.55, voice_weight=1.45, dips=(), fade_out=0.3, duck_release=350):
    """dips: [(t0, depth), ...] music volume ramps down by `depth` (0..1) over 0.6 s from t0 and stays down."""
    music = music if os.path.isabs(music) else os.path.join(ROOT, music)
    vol = str(music_level)
    for t0, depth in dips:
        vol = f"({vol})*(1-{depth}*min(max((t-{t0})/0.6\\,0)\\,1))"
    inputs = ["-ss", str(music_start), "-t", str(dur), "-i", music, "-i", voice_wav]
    fc = (
        f"[1:a]aformat=channel_layouts=mono,highpass=f=85,equalizer=f=3200:t=q:w=1.2:g=2.5,"
        f"acompressor=threshold=-20dB:ratio=3:attack=5:release=120:makeup=2,adelay={int(vo_offset * 1000)},apad,"
        f"atrim=0:{dur},asplit=2[vo][sc];"
        f"[0:a]aformat=channel_layouts=stereo,volume='{vol}':eval=frame,"
        f"afade=t=in:d=0.05,afade=t=out:st={dur - fade_out}:d={fade_out}[mus];"
        f"[sc]aformat=channel_layouts=stereo[sc2];"
        f"[mus][sc2]sidechaincompress=threshold=0.035:ratio=6:attack=12:release={duck_release}:makeup=1[duck];"
        f"[vo]aformat=channel_layouts=stereo[vo2];"
    )
    if sfx_wav:
        inputs += ["-i", sfx_wav]
        fc += f"[2:a]aformat=channel_layouts=stereo[fx];[duck][vo2][fx]amix=inputs=3:normalize=0:weights=1 {voice_weight} 1,"
    else:
        fc += f"[duck][vo2]amix=inputs=2:normalize=0:weights=1 {voice_weight},"
    fc += (f"loudnorm=I=-14:TP=-1.5:LRA=9,volume={gain_db}dB,"
           f"alimiter=limit={limit}:attack=2:release=60:level=disabled,aresample=48000[a]")
    subprocess.run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", fc, "-map", "[a]",
                    "-c:a", "pcm_s16le", out_wav], check=True)
    return out_wav


def mix_from_cfg(project_dir, dur, sfx_wav=None, dips=(), music_start=None):
    """mix() with the `audio:` block of project.yaml (music, music_start, gain_db, limit, music_level, ...)."""
    from .common import load_cfg, out_dir
    cfg = load_cfg(project_dir); a = dict(cfg.get("audio", {}))
    a.pop("music_align", None)
    return mix(os.path.join(out_dir(project_dir), "mix.wav"), dur, os.path.join(project_dir, "voice", "vo_full.wav"),
               a.pop("music"), a.pop("music_start") if music_start is None else music_start, sfx_wav=sfx_wav,
               vo_offset=cfg.get("vo_offset", 0.5), dips=list(dips) + [tuple(d) for d in a.pop("dips", [])],
               **{k: v for k, v in a.items() if k in ("gain_db", "limit", "music_level", "voice_weight", "fade_out", "duck_release")})


def loudness(path):
    """{'lufs': integrated loudness, 'peak': true peak dBFS} of any audio/video file."""
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    lufs = peak = None
    for l in r.splitlines():
        l = l.strip()
        if l.startswith("I:"): lufs = float(l.split()[1])
        if l.startswith("Peak:"): peak = float(l.split()[1])
    return dict(lufs=lufs, peak=peak)


def mux(video, audio, final):
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", video, "-i", audio,
                    "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-movflags", "+faststart",
                    "-shortest", final], check=True)
    ld = loudness(final)
    print(f"  {os.path.basename(final)}: {ld['lufs']} LUFS, true peak {ld['peak']} dBFS"
          + ("  <-- WARNING clipping risk, lower audio.limit" if ld["peak"] is not None and ld["peak"] > -1.0 else ""))
    return final


def mux_project(project_dir):
    from .common import out_dir
    o = out_dir(project_dir); name = os.path.basename(os.path.normpath(project_dir))
    return mux(os.path.join(o, "graphics.mp4"), os.path.join(o, "mix.wav"), os.path.join(o, f"{name}.mp4"))
