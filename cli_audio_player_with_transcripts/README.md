# CLI Audio Player with Transcripts

A terminal-based audio player that synchronizes audio playback with transcripts, designed to work with [WhisperX](https://github.com/m-bain/whisperX) output files.

![Demo Screenshot](screenshot.png)

## Features

- Synchronized audio playback with transcript display
- Word-level highlighting as audio plays
- Speaker diarization display support
- Progress bar and timestamp display
- Playback controls:
  - Space: Play/Pause
  - ←/→: Skip ±5 seconds
  - Shift + ←/→: Skip ±30 seconds
  - ↑/↓: Volume control
  - C: Copy current segment to clipboard
  - Q: Quit and save position
- Position saving between sessions
- Multi-speaker support with color coding

## Installation

```bash
# Install dependencies
pip install sounddevice soundfile rich numpy pynput pyperclip
```

## Usage

```bash
python terminal_player.py audio.wav audio.json
```

The player expects:
- An audio file (wav format)
- A JSON transcript file (WhisperX format)

## Requirements

- Python 3.10+
- Audio file in WAV format
- Transcript file in WhisperX JSON format
- Terminal with Unicode support

## Acknowledgements

100% written by Claude Sonnet 3.5

## License

MIT