// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface IMarketPriceFeed {
    function priceForTrade(string memory _token, uint256 value, uint256 maxValue, bool _maximise) external view returns (uint256);

    function priceForPool(string memory _token, bool _maximise) external view returns (uint256);

    function priceForLiquidate(string memory _token, bool _maximise) external view returns (uint256);

    function priceForIndex(string memory _token, bool _maximise) external view returns (uint256);

    function getLatestPrimaryPrice(string memory _token) external view returns (uint256);
}

