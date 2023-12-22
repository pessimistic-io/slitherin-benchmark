// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface IMevController {
    function pre(address sender1, address sender2) external;
    function post(address sender1, address sender2) external;
}

