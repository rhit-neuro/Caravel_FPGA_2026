"""
load_bitstream_uboot.py

Programs the KR260's FPGA through U-Boot instead of JTAG:
  1. U-Boot "loadx" receives the .bit file over the serial port (XMODEM-1K)
  2. U-Boot "fpga loadb" programs the FPGA with it

Going through U-Boot matters: its fpga command asks the PMU firmware to power
up the FPGA fabric (PL) and connect it to the processor system, which JTAG
programming alone does not do on the KR260.

Usage:  python load_bitstream_uboot.py ddr_tester_100MHz.bit [COM11]
"""
import os
import sys
import time

import serial

LOAD_ADDRESS = 0x10000000          # free DDR, below the 0x40000000 test area
BLOCK_SIZE = 1024                  # XMODEM-1K block
START_1K_BLOCK, END_OF_TRANSFER = 0x02, 0x04
ACKNOWLEDGE, NOT_ACKNOWLEDGE, CRC_REQUEST = 0x06, 0x15, ord("C")


def crc16(data):
    """CRC-16/XMODEM (polynomial 0x1021), as XMODEM-CRC expects."""
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def read_until(port, text, timeout_seconds):
    """Read serial output until `text` appears (or time runs out)."""
    received = b""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        received += port.read(port.in_waiting or 1)
        if text.encode() in received:
            break
    return received.decode(errors="replace")


def send_xmodem(port, data):
    """Send `data` with XMODEM-1K, after the receiver asks for CRC mode."""
    # Wait for U-Boot to send 'C' (start, CRC mode)
    deadline = time.time() + 30
    while port.read(1) != bytes([CRC_REQUEST]):
        if time.time() > deadline:
            raise RuntimeError("U-Boot never asked for the file")

    blocks = [data[i:i + BLOCK_SIZE] for i in range(0, len(data), BLOCK_SIZE)]
    for number, block in enumerate(blocks, start=1):
        block = block.ljust(BLOCK_SIZE, b"\x1A")             # pad the last block
        packet = (bytes([START_1K_BLOCK, number & 0xFF, 0xFF - (number & 0xFF)])
                  + block + crc16(block).to_bytes(2, "big"))
        for attempt in range(10):
            port.write(packet)
            reply = port.read(1)
            if reply == bytes([ACKNOWLEDGE]):
                break
        else:
            raise RuntimeError(f"block {number} was never acknowledged")
        if number % 100 == 0 or number == len(blocks):
            print(f"  sent {number}/{len(blocks)} blocks", flush=True)

    port.write(bytes([END_OF_TRANSFER]))
    port.read(1)


def main():
    bitstream_path = sys.argv[1]
    port_name = sys.argv[2] if len(sys.argv) > 2 else "COM11"
    bitstream = open(bitstream_path, "rb").read()
    print(f"{os.path.basename(bitstream_path)}: {len(bitstream)} bytes")

    with serial.Serial(port_name, 115200, timeout=5) as port:
        port.write(b"\r")
        read_until(port, "ZynqMP>", 3)

        # 1. Receive the file into DDR
        port.write(f"loadx 0x{LOAD_ADDRESS:x}\r".encode())
        start_time = time.time()
        send_xmodem(port, bitstream)
        print(read_until(port, "ZynqMP>", 10).strip())
        print(f"  transfer took {time.time() - start_time:.0f} s")

        # 2. Program the FPGA (U-Boot strips the .bit header itself)
        port.write(f"fpga loadb 0 0x{LOAD_ADDRESS:x} 0x{len(bitstream):x}\r".encode())
        output = read_until(port, "ZynqMP>", 30)
        print(output.strip())
        # U-Boot prints nothing extra on success, only an error message on failure
        if "fail" in output.lower() or "error" in output.lower():
            sys.exit("FPGA programming through U-Boot failed")
        print("FPGA programmed")


if __name__ == "__main__":
    main()
