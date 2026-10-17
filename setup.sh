#!/usr/bin/env bash
# Environment setup for the reel factory. Paste the body of this file into the cloud environment's "Setup script"
# (Environment settings -> Setup script) so every new session starts with everything installed and cached.
# ffmpeg, Python 3, PIL and numpy are pre-installed in Claude Code cloud VMs.
set -e
pip install -q "rembg[cpu]" faster-whisper opencv-python-headless pyyaml
# pre-download the models so the first reel doesn't wait for them
python3 -c "from faster_whisper import WhisperModel; WhisperModel('medium.en', device='cpu', compute_type='int8'); WhisperModel('small.en', device='cpu', compute_type='int8')"
python3 -c "from rembg import new_session; new_session('isnet-general-use')"
