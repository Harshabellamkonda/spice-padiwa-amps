#!/bin/sh
# please adapt to your LTspice IV installation
wine "C:\\Program Files\\LTC\\LTspiceIV\\scad3.exe" \
    -run -b padiwa-amps.asc 2>/dev/null
