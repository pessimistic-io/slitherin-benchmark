// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./DataTypes.sol";

interface IJudgementCondition {
    function judgementConditionAmount(
        address productPoolAddress,
        uint256 productId
    ) external view returns (DataTypes.ProgressStatus);
}

