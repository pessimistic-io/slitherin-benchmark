// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./IProductIRSModule.sol";
import { IVammModule } from "./IVammModule.sol";
import "./Config.sol";

/**
 * @title Performs swaps and settements on top of the v2 dated irs instrument
 */
library V2DatedIRS {
    // todo: add price limit in here once implemented in the dated irs instrument
    function swap(uint128 accountId, uint128 marketId, uint32 maturityTimestamp, int256 baseAmount, uint160 priceLimit)
        internal
        returns (int256 executedBaseAmount, int256 executedQuoteAmount, uint256 fee, uint256 im, int24 currentTick)
    {
        (executedBaseAmount, executedQuoteAmount, fee, im) = IProductIRSModule(Config.load().VOLTZ_V2_DATED_IRS_PROXY)
            .initiateTakerOrder(accountId, marketId, maturityTimestamp, baseAmount, priceLimit);
        // get current tick
        currentTick = IVammModule(Config.load().VOLTZ_V2_DATED_IRS_VAMM_PROXY).getVammTick(marketId, maturityTimestamp);
    }

    function settle(uint128 accountId, uint128 marketId, uint32 maturityTimestamp) internal {
        IProductIRSModule(Config.load().VOLTZ_V2_DATED_IRS_PROXY).settle(accountId, marketId, maturityTimestamp);
    }
}

