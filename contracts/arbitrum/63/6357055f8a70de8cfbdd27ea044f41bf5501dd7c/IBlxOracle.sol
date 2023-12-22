// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AbdkUtil.sol";

// Oracle for BLX/USD price
interface IBlxOracle {
    function getBlxUsdRate() external view returns (int128);
}

