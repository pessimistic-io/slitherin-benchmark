// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;
pragma abicoder v2;

interface IFastPriceFeed {
    function setPrices(string[] memory _tokens, uint128[] memory _prices, uint32[] memory _timestamps) external;
}

