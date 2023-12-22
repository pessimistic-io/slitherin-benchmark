// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IGlpManager {
    function getPrice(bool) external view returns (uint);
}
