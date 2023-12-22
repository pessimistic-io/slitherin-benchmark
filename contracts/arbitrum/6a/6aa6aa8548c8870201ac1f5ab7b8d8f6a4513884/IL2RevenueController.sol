// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IL2RevenueController {
    function sendToL1(uint256 ethAmount, bytes calldata bridgeData) external;
    function withdrawTerminalFees(address _token, bytes calldata _oneInchData) external;
}

