import supervisor
import usb_hid

# =========================
# CONFIG PAR PANEL
# =========================
PANEL_NUM = 1  # <-- mets 1..20 (commence à +1)
PRODUCT_NAME = f"SF1 Pneumatic Panel #{PANEL_NUM}"

# =========================
# USB IDENTIFICATION
# =========================
# VID Adafruit (shared) : 0x239A
# PID custom (évite le PID CircuitPython 0x80F4)
VID = 0x239A
PID_BASE = 0x9000
PID = PID_BASE + PANEL_NUM  # => 0x9001..0x9014 pour 1..20

supervisor.set_usb_identification(
    manufacturer="Nelfe Arcade",
    product=PRODUCT_NAME,
    vid=VID,
    pid=PID
)

# =========================
# HID CUSTOM ONLY
# =========================
usb_hid.disable()

DESC = bytes((
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x05,        # Usage (Game Pad)
    0xA1, 0x01,        # Collection (Application)
    0x85, 0x01,        # Report ID = 1

    # 16 Buttons
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x10,
    0x15, 0x00,
    0x25, 0x01,
    0x95, 0x10,
    0x75, 0x01,
    0x81, 0x02,

    # X, Y (signed -127..127)
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x15, 0x81,
    0x25, 0x7F,
    0x75, 0x08,
    0x95, 0x02,
    0x81, 0x02,

    # Slider + Dial (0..255)
    0x09, 0x36,
    0x09, 0x37,
    0x15, 0x00,
    0x26, 0xFF, 0x00,
    0x75, 0x08,
    0x95, 0x02,
    0x81, 0x02,

    0xC0
))

panel = usb_hid.Device(
    report_descriptor=DESC,
    usage_page=0x01,
    usage=0x05,
    report_ids=(1,),
    in_report_lengths=(6,),
    out_report_lengths=(0,),
)

usb_hid.enable((panel,))