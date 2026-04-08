# Project #10: Temperature-controlled fan

Reads temperature through an **ADC0804** and **8255**, shows it on screen, drives **LEDs** and a **motor** (two rough “speeds”), and trips a **buzzer** with the motor off from **100 °C** upward. There’s a long pause between samples so it feels like a slow monitoring loop, not a tight poll.

## Hardware

| Part | Role |
|------|------|
| LM35 | Analog temp |
| ADC0804 | 8-bit conversion |
| 8255 | A from ADC, B to LEDs/motor, C for ADC control + buzzer |
| Driver (e.g. L293D) | Motor |
| LEDs / buzzer | Status + alarm |

**8255** at **00F8h** (emu default): control **98h** — port A in, B out, **PC7–4** inputs, **PC3–0** outputs. Tie **ADC0804 INTR** to **PC4** (low when conversion finished). **PC0–2** are your WR/RD/buzzer lines; match levels to your board (0804 /WR and /RD are active low — use inverters if needed).

The code keeps **PC_SHADOW** for the bottom three bits so strobing the ADC doesn’t accidentally clear the buzzer latch. Only **00000111b** is written to port C.

If **98h** gives trouble in emu or on wire, use **90h** (all of C out), handle INTR elsewhere or skip it, and turn **WAIT_ADC** into a longer fixed delay.

## What you’ll see

| Temp | Fan | LED | Buzzer |
|------|-----|-----|--------|
| &lt; 30 °C | Off | Green | Off |
| 30–59 | Slower toggling | Yellow | Off |
| 60–99 | Faster toggling | Red | Off |
| ≥ 100 | Off | Red flash | On |

“Speed” is just software on/off timing — no timer chip PWM.

## Numbers in the .asm

For **emu8086**, port A is whatever byte you type; the program maps **0–255 → 0–100 °C** with `×100/255` so the 30 / 60 / 100 compares make sense. On a real board, replace that bit with proper LM35 + reference math if you want real °C.

Test bands on port A (rough): **0–76** cool, **77–152** mid, **153–254** hot, **255** emergency.

**WAIT_ADC** waits a little, then polls **PC4** until it’s low or gives up after a timeout so the sim won’t hang if INTR isn’t wired.

## Run

Open `Project #10 - Temperature-Controlled Fan System.asm` in emu8086, assemble, run, drive **F8h** as input.

## Author

Muawia Amir — BS AI, NFC IET Multan.
