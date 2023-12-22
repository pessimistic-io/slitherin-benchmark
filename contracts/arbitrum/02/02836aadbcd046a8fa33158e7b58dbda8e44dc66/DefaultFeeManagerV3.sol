// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity ^0.8.9;
import "./IFeeManager.sol";
import "./IDCAStrategyManagerV3.sol";
import "./DCATypes.sol";

contract DefaultFeeManagerV3 is IFeeManager {
    uint256 constant DENOMINATOR = 1000000;
    IDCAStrategyManagerV3 dcaStrategyManager;

    constructor(address dcaStrategyManager_) {
        dcaStrategyManager = IDCAStrategyManagerV3(dcaStrategyManager_);
    }

    function getFeePercentage(
        uint256 strategyId,
        address /*user*/
    ) public view returns (uint256) {
        DCATypes.StrategyDataV3 memory strategyData = dcaStrategyManager
            .getStrategy(strategyId);
        return strategyData.strategyFee;
    }

    function calculateFee(
        uint256 strategyId,
        address user,
        uint256 amount
    ) external view returns (uint256) {
        uint256 strategyFee = getFeePercentage(strategyId, user);
        uint256 fee = (amount * strategyFee) / DENOMINATOR;

        return fee;
    }
}

