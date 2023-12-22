// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.0;

contract Constants {
    uint internal constant Q64  = 1 << 64;
    uint internal constant Q80  = 1 << 80;
    uint internal constant Q192 = 1 << 192;
    uint internal constant Q255 = 1 << 255;
    uint internal constant Q128 = 1 << 128;
    uint internal constant Q256M = type(uint).max;

    uint internal constant SIDE_R = 0x00;
    uint internal constant SIDE_A = 0x10;
    uint internal constant SIDE_B = 0x20;
    uint internal constant SIDE_C = 0x30;
}
