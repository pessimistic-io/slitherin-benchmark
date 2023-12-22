// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

import "./IVaultProtector.sol";
import { Math } from "./Math.sol";

contract VaultProtector is IVaultProtector {
    using Math for uint256;

    function getMaxPredictAmount(
        uint256 vaultBalance,
        uint256 predictionPerc,
        uint256 minPredictionPerc,
        uint256 roundDownPredictAmount,
        uint256 roundUpPredictAmount,
        uint256 predictedAmount,
        bool nextPredictionUp
    ) external pure override returns (uint256 maxAmount) {
        uint256 DENOMINATOR = 10000;
        uint256 maxPredictAmount = (vaultBalance * predictionPerc) / DENOMINATOR;
        return maxPredictAmount;
    }
}

