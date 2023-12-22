// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

struct VerifierInfo {
    uint[2] a;
    uint[2][2] b;
    uint[2] c;
    bytes bh;
    bytes ds;
    bytes rb;
    bytes32 base;
    bytes e;
    bytes body;
}
