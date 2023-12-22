// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Strategy Utils
 * @author  Pulsar Finance
 * @dev     VERSION: 1.0
 *          DATE:    2023.10.05
 */

import {PercentageMath} from "./PercentageMath.sol";

library StrategyUtils {
    function buyPercentagesSum(
        uint256[] memory buyPercentages
    ) internal pure returns (uint256 sumOfBuyPercentages) {
        for (uint256 i = 0; i < buyPercentages.length; i++) {
            require(buyPercentages[i] > 0, "Buy percentage must be gt zero");
            sumOfBuyPercentages += buyPercentages[i];
        }
    }
}

