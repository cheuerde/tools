# pip install sounddevice soundfile rich numpy pynput pyperclip
import json
import sounddevice as sd
import soundfile as sf
from rich.live import Live
from rich.text import Text
from rich.console import Console
import sys
from pathlib import Path
import time
import numpy as np
import threading
from pynput import keyboard

class TerminalAudioPlayer:
    def __init__(self, audio_path, json_path):
        # Load audio file
        self.audio_data, self.sample_rate = sf.read(audio_path)
        if len(self.audio_data.shape) > 1:
            self.audio_data = self.audio_data.mean(axis=1)
        
        self.duration = len(self.audio_data) / self.sample_rate
        
        # Load transcript
        with open(json_path, 'r', encoding='utf-8') as f:
            self.transcript = json.load(f)
        
        # Pre-process transcript for faster lookups
        self.process_transcript()
            
        # Setup display
        self.console = Console()
        self.current_time = 0
        self.is_playing = True
        self.is_paused = False
        self.last_word_index = None
        self.last_segment_index = None
        
        # Playback control
        self.stream = None
        self.seek_lock = threading.Lock()
        
    def process_transcript(self):
        """Pre-process transcript for more efficient lookups"""
        # Create time-indexed structures
        self.segments_indexed = []
        for idx, segment in enumerate(self.transcript['segments']):
            self.segments_indexed.append({
                'start': segment['start'],
                'end': segment['end'],
                'index': idx,
                'words': segment.get('words', []),
                'text': segment['text'],
                'speaker': segment.get('speaker', '')
            })
    
    def find_current_position(self, current_time):
        """Binary search for current segment and word"""
        # Find segment
        current_segment = None
        current_word = None
        
        # Use last known position as optimization
        if (self.last_segment_index is not None and 
            self.last_segment_index < len(self.segments_indexed)):
            segment = self.segments_indexed[self.last_segment_index]
            if segment['start'] <= current_time <= segment['end']:
                current_segment = segment
            elif current_time > segment['end'] and self.last_segment_index + 1 < len(self.segments_indexed):
                next_segment = self.segments_indexed[self.last_segment_index + 1]
                if next_segment['start'] <= current_time <= next_segment['end']:
                    self.last_segment_index += 1
                    current_segment = next_segment
        
        # If not found, do binary search
        if current_segment is None:
            left, right = 0, len(self.segments_indexed) - 1
            while left <= right:
                mid = (left + right) // 2
                segment = self.segments_indexed[mid]
                if segment['start'] <= current_time <= segment['end']:
                    current_segment = segment
                    self.last_segment_index = mid
                    break
                elif current_time < segment['start']:
                    right = mid - 1
                else:
                    left = mid + 1
        
        # Find word within segment, with safety checks
        if current_segment and current_segment.get('words'):
            for word in current_segment['words']:
                if not all(key in word for key in ['start', 'end', 'word']):
                    continue
                try:
                    if word['start'] <= current_time <= word['end']:
                        current_word = word
                        break
                except (TypeError, ValueError):
                    continue
        
        return current_segment, current_word

    def format_time(self, seconds):
        minutes = int(seconds // 60)
        seconds = int(seconds % 60)
        return f"{minutes:02d}:{seconds:02d}"
        
    def get_current_text(self, current_time):
        try:
            # Find current segment and word with optimized search
            current_segment, current_word = self.find_current_position(current_time)
                    
            if current_segment:
                # Create the progress bar
                progress = int((current_time / self.duration) * 20)
                progress_bar = f"[{'=' * progress}{' ' * (20-progress)}]"
                
                # Format time
                time_display = f"{self.format_time(current_time)}/{self.format_time(self.duration)}"
                
                # Create text with highlighted word
                text = Text()
                text.append(f"{progress_bar} {time_display} ")
                
                # Add playback status
                status = "⏸️ " if self.is_paused else "▶️ "
                text.append(status)
                
                # Add speaker label if available
                if current_segment.get('speaker'):
                    text.append(f"[Speaker {current_segment['speaker']}] ", style="bold blue")
                
                # Add words with highlighting
                if current_word and 'word' in current_word:
                    current_word_clean = current_word['word'].strip('.,!?').lower()
                else:
                    current_word_clean = None
                
                for word in current_segment['text'].split():
                    word_clean = word.strip('.,!?').lower()
                    
                    if current_word_clean and word_clean == current_word_clean:
                        text.append(word, style="bold yellow")
                    else:
                        text.append(word)
                    text.append(" ")
                
                # Add controls help
                text.append("\n[Space: Play/Pause] [←: -5s] [→: +5s] [q: Quit]", style="dim")
                    
                return text
        except Exception as e:
            # Fallback display in case of any error
            text = Text()
            text.append(f"[{'=' * int((current_time / self.duration) * 20)}{' ' * (20-int((current_time / self.duration) * 20))}] ")
            text.append(f"{self.format_time(current_time)}/{self.format_time(self.duration)} ")
            text.append("Processing...")
            return text
            
        return Text("Loading...")

    def audio_callback(self, outdata, frames, time_info, status):
        if status:
            print(status)
        
        if self.is_paused:
            outdata.fill(0)
            return
            
        with self.seek_lock:
            current_sample = int(self.current_time * self.sample_rate)
            end_sample = current_sample + frames
            
            if end_sample > len(self.audio_data):
                self.is_playing = False
                raise sd.CallbackStop()
                
            outdata[:] = self.audio_data[current_sample:end_sample, np.newaxis]
            self.current_time += frames / self.sample_rate

    def seek(self, offset):
        """Seek forward or backward by offset seconds"""
        with self.seek_lock:
            new_time = max(0, min(self.current_time + offset, self.duration))
            self.current_time = new_time

    def toggle_pause(self):
        """Toggle pause state"""
        self.is_paused = not self.is_paused

    def on_press(self, key):
        """Handle keyboard press events"""
        try:
            if key == keyboard.Key.space:
                self.toggle_pause()
            elif key == keyboard.Key.left:
                self.seek(-5)
            elif key == keyboard.Key.right:
                self.seek(5)
            elif hasattr(key, 'char') and key.char == 'q':
                self.is_playing = False
                return False  # Stop listener
        except AttributeError:
            pass

    def start_keyboard_listener(self):
        """Start keyboard listener in a separate thread"""
        listener = keyboard.Listener(on_press=self.on_press)
        listener.start()
        return listener

    def play(self):
        try:
            # Start keyboard listener
            listener = self.start_keyboard_listener()
            
            with Live("", refresh_per_second=20, transient=True) as live:
                with sd.OutputStream(
                    channels=1,
                    callback=self.audio_callback,
                    samplerate=self.sample_rate,
                    blocksize=int(self.sample_rate * 0.05)  # 50ms blocks for more precise timing
                ) as self.stream:
                    while self.is_playing:
                        live.update(self.get_current_text(self.current_time))
                        time.sleep(0.05)
                        
        except KeyboardInterrupt:
            print("\nPlayback stopped.")
            self.is_playing = False
        finally:
            listener.stop()  # Stop keyboard listener
            print("\nPlayback finished.")

def main():
    if len(sys.argv) != 3:
        print("Usage: python script.py <audio_file> <json_file>")
        sys.exit(1)
        
    audio_path = Path(sys.argv[1])
    json_path = Path(sys.argv[2])
    
    if not audio_path.exists():
        print(f"Error: Audio file not found: {audio_path}")
        sys.exit(1)
        
    if not json_path.exists():
        print(f"Error: JSON file not found: {json_path}")
        sys.exit(1)
    
    try:
        player = TerminalAudioPlayer(audio_path, json_path)
        player.play()
    except Exception as e:
        print(f"Error during playback: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()