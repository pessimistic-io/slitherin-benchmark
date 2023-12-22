// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IClaimProcessor {
    function processClaim(address recipient, uint256 amount) external returns (bool);
}

