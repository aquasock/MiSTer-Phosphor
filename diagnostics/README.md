# Visualizer response diagnostic

`visualizer_response_44100.wav` is stereo 16-bit PCM at 44.1 kHz. Record the
core's HDMI video and audio from before playback starts until the file ends.
Do not pause or open the OSD during the test.

Event timeline:

| Time | Signal |
|---:|---|
| 0-2 s | Silence/baseline |
| 2-4 s | 1 kHz, left and right in phase |
| 4-6 s | Silence |
| 6-8 s | 100 Hz, left and right in phase |
| 8-10 s | Silence |
| 10-12 s | 8 kHz, left and right in phase |
| 12-14 s | Silence |
| 14-16 s | 440 Hz left, 660 Hz right |
| 16-18 s | Silence |
| 18-20 s | 440 Hz quadrature: right leads left by 90 degrees (XY circle) |
| 20-22 s | Silence |
| 22-26 s | 1 kHz gated 250 ms on / 250 ms off (eight pulses) |
| 26-28 s | Silence/decay observation |

Each tone uses 72% full-scale amplitude. The hard, sample-aligned boundaries
provide reference edges in the captured audio track. Comparing those edges to
the first visual change measures onset latency; comparing tone-off edges to
the return to baseline measures release/decay behavior.

## Gapless album-loop diagnostic

`gapless_stereo_sine_4s.flac` is a four-second, stereo, 44.1 kHz, 16-bit FLAC
with exactly 176,400 samples (300 CD sectors). The left channel is 440 Hz with
a 0.3-radian starting phase; the right channel is 660 Hz with a 0.7-radian
starting phase. Both tones use 50% full scale.

Each channel completes an integer number of cycles in four seconds. There is
no leading or trailing silent frame, and concatenating two decoded copies is
sample-for-sample identical to generating the same oscillators continuously
for eight seconds. Add two or more copies to the FLAC Album Builder with
Circular album enabled and Tight loop boundary trim disabled. A correct
final-to-first repeat remains a continuous tone indefinitely; any interruption
is introduced by playback rather than the source material.

## XY circle/crosshair diagnostic

`xy_circle_crosshair_4s.flac` is a 44.1 kHz, 16-bit stereo XY beam path. In
O-Scope mode it draws a full-scale circle with centered horizontal and
vertical diameters. The connected path repeats at exactly 180 Hz--three full
redraws per 60 Hz video frame--and the four-second file boundary is
sample-continuous. Repeated copies can therefore be packaged as a circular
album without adding an unintended retrace line or changing display phase.
