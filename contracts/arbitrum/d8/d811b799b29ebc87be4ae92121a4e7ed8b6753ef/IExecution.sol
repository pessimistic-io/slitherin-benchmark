// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./DataTypes.sol";
import "./ICustomerPool.sol";

interface IExecution {
    function executeWithRewards(
        address productPoolAddress,
        uint256 customerId,
        address customerAddress,
        uint256 productId,
        ICustomerPool customerPool,
        address stableC
    ) external view returns (DataTypes.CustomerByCrypto memory, DataTypes.CustomerByCrypto memory);
}

