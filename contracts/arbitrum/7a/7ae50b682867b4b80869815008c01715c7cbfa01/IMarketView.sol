// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./Constant.sol";

interface IMarketView {
    function borrowRatePerSec(address gToken) external view returns (uint256);

    function supplyRatePerSec(address gToken) external view returns (uint256);
}

