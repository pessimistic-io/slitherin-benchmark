// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./DataTypes.sol";
import "./IProductPool.sol";
import "./ICustomerPool.sol";

interface IApplyBuyIntent {
    function dealApplyBuyCryptoQuantity(
        uint256 amount,
        uint256 _pid,
        IProductPool productPool,
        address stableC
    ) external view returns (uint256, address);

    function dealSoldCryptoQuantity(
        uint256 amount,
        DataTypes.ProductInfo memory product,
        address stableC
    ) external pure returns (uint256);
}

