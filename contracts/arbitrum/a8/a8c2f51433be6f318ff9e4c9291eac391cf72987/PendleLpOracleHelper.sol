// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PendleLpOracleLib} from "./PendleLpOracleLib.sol";
import {IPMarket} from "./IPMarket.sol";

contract PendleLpOracleHelper {
    using PendleLpOracleLib for IPMarket;

    function getLpToAssetRate(
        IPMarket market,
        uint32 duration
    ) external view returns (uint256 lpToAssetRate) {
        return market.getLpToAssetRate(duration);
    }
}

