// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IPriceFeed {
    // get latest price
    function getPrice(bytes32 _priceFeedKey) external view returns (uint256);
}

