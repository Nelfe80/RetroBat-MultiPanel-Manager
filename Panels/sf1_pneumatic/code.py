import time
import board
import analogio
import digitalio

# HID
import usb_hid
dev = usb_hid.devices[0]
REPORT_ID = 1

# Buttons mapping (1..16)
BTN_START = 9
BTN_COIN  = 10

# FSR calibration/thresholds
BASELINE_TIME_S = 0.2
DEADZONE_RAW = 200

PRESS_THRESHOLD_RAW = 800
RELEASE_THRESHOLD_RAW = 500
COOLDOWN_MS = 50.0

# HIT levels by hold time (because FSR saturates)
HIT2_HOLD_MS = 230.0
HIT3_HOLD_MS = 450.0

# Pedal output levels (0..255)
LEVEL_1 = 90
LEVEL_2 = 170
LEVEL_3 = 255

# Pins
adc_punch = analogio.AnalogIn(board.A0)  # Punch -> Accelerator
adc_kick  = analogio.AnalogIn(board.A1)  # Kick  -> Brake

JOY_UP_PIN    = board.GP18
JOY_DOWN_PIN  = board.GP19
JOY_LEFT_PIN  = board.GP20
JOY_RIGHT_PIN = board.GP21

START_PIN = board.GP16
COIN_PIN  = board.GP17

def make_input(pin):
    d = digitalio.DigitalInOut(pin)
    d.direction = digitalio.Direction.INPUT
    d.pull = digitalio.Pull.UP
    return d

joy_up = make_input(JOY_UP_PIN)
joy_down = make_input(JOY_DOWN_PIN)
joy_left = make_input(JOY_LEFT_PIN)
joy_right = make_input(JOY_RIGHT_PIN)

btn_start = make_input(START_PIN)
btn_coin  = make_input(COIN_PIN)

def calibrate_baseline(adc, duration_s):
    t0 = time.monotonic()
    s = 0
    n = 0
    while time.monotonic() - t0 < duration_s:
        s += adc.value
        n += 1
        time.sleep(0.004)
    return int(s / max(1, n))

def read_delta(raw, baseline):
    d = raw - baseline
    if abs(d) < DEADZONE_RAW:
        return 0
    return max(0, d)

def strength_from_hold_ms(hold_ms):
    if hold_ms >= HIT3_HOLD_MS:
        return 3
    if hold_ms >= HIT2_HOLD_MS:
        return 2
    return 1

def pedal_from_strength(s):
    if s == 3:
        return LEVEL_3
    if s == 2:
        return LEVEL_2
    return LEVEL_1

def joy_axes():
    # pressed = LOW (pull-up)
    up = not joy_up.value
    down = not joy_down.value
    left = not joy_left.value
    right = not joy_right.value

    ax = 0
    ay = 0
    if left and not right:
        ax = -127
    elif right and not left:
        ax = 127

    if up and not down:
        ay = -127
    elif down and not up:
        ay = 127

    return ax, ay

# Report layout (6 bytes):
# [0..1] buttons (16-bit)
# [2] X (int8)
# [3] Y (int8)
# [4] Accelerator (uint8)
# [5] Brake (uint8)

buttons_state = 0
x = 0
y = 0
accel = 0
brake = 0

report = bytearray(6)

def send_report():
    report[0] = buttons_state & 0xFF
    report[1] = (buttons_state >> 8) & 0xFF
    report[2] = x & 0xFF
    report[3] = y & 0xFF
    report[4] = accel & 0xFF
    report[5] = brake & 0xFF
    dev.send_report(report, report_id=REPORT_ID)

def set_button(btn_num, pressed):
    global buttons_state
    mask = 1 << (btn_num - 1)
    if pressed:
        buttons_state |= mask
    else:
        buttons_state &= ~mask

# Start/Coin debounce
last_start = False
last_coin = False
last_btn_t = 0.0
BTN_DEBOUNCE_MS = 25.0

def update_meta_buttons(now):
    global last_start, last_coin, last_btn_t

    start_pressed = not btn_start.value
    coin_pressed  = not btn_coin.value

    if (now - last_btn_t) * 1000.0 < BTN_DEBOUNCE_MS:
        return

    if start_pressed != last_start:
        last_btn_t = now
        last_start = start_pressed
        set_button(BTN_START, start_pressed)
        print("START", "DOWN" if start_pressed else "UP")

    if coin_pressed != last_coin:
        last_btn_t = now
        last_coin = coin_pressed
        set_button(BTN_COIN, coin_pressed)
        print("COIN", "DOWN" if coin_pressed else "UP")

print("Calibrating baselines (~%.1fs, do not touch)..." % BASELINE_TIME_S)
base_p = calibrate_baseline(adc_punch, BASELINE_TIME_S)
base_k = calibrate_baseline(adc_kick,  BASELINE_TIME_S)
print("Punch baseline:", base_p)
print("Kick  baseline:", base_k)
print("READY: X/Y joystick, Accelerator=punch, Brake=kick, Start/Coin buttons")
print("-" * 80)

send_report()

# Winner-takes-all FSR arbitration
active = 0  # 0 none, 1 punch, 2 kick
press_t0 = 0.0
last_release_t = time.monotonic()

while True:
    now = time.monotonic()

    # joystick + meta buttons
    x, y = joy_axes()
    update_meta_buttons(now)

    # raw deltas
    dp = read_delta(adc_punch.value, base_p)
    dk = read_delta(adc_kick.value,  base_k)

    # cooldown after release
    if active == 0 and (now - last_release_t) * 1000.0 < COOLDOWN_MS:
        accel = 0
        brake = 0
        send_report()
        time.sleep(0.001)
        continue

    if active == 0:
        # Start press on strongest delta
        if dp > PRESS_THRESHOLD_RAW or dk > PRESS_THRESHOLD_RAW:
            active = 1 if dp >= dk else 2
            press_t0 = now

    else:
        hold_ms = (now - press_t0) * 1000.0
        s = strength_from_hold_ms(hold_ms)
        #level = pedal_from_strength(s)
        level = 255
        
        if active == 1:
            # Punch -> Accelerator
            accel = level
            brake = 0

            # Release?
            if dp < RELEASE_THRESHOLD_RAW:
                print("PUNCH HIT%d | hold=%4.0fms | ACC=%d" % (s, hold_ms, accel))
                accel = 0
                active = 0
                last_release_t = now

        else:
            # Kick -> Brake
            brake = level
            accel = 0

            if dk < RELEASE_THRESHOLD_RAW:
                print("KICK  HIT%d | hold=%4.0fms | BRK=%d" % (s, hold_ms, brake))
                brake = 0
                active = 0
                last_release_t = now

    send_report()
    time.sleep(0.001)