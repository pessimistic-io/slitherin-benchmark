// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IVaultPriceFeed {
    function setTokenConfig(address _token, address _priceFeed, uint256 _priceDecimals) external;

    function getLastPrice(address _token) external view returns (uint256, uint256, bool);

    function getLastPrices(address[] memory _tokens) external view returns(uint256[] memory, bool);

    function setLatestPrice(address _token, uint256 _latestPrice) external;
}
