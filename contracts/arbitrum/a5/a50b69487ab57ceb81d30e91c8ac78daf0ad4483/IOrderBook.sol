// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IStorageSet.sol";

interface IOrderBook is IStorageSet{
    struct Order{
        uint256 orderIndex;
        bool isInc;
        address account;
        address collateralToken;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        uint256 executionFee;
        bool triggerAboveThreshold;
    }

    function getIncreaseOrder(address _account, uint256 _orderIndex) external view returns (Order memory);
    function getDecreaseOrder(address _account, uint256 _orderIndex) external view returns (Order memory);
}

