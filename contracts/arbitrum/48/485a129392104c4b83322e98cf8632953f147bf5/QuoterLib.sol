//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IQuoter} from "./IQuoter.sol";

import {Instrument, PositionId, Symbol} from "./libraries_DataTypes.sol";

import {IContangoView} from "./IContangoView.sol";
import {IFeeModel} from "./IFeeModel.sol";
import {ContangoPositionNFT} from "./ContangoPositionNFT.sol";

library QuoterLib {
    function spot(IQuoter quoter, Instrument memory instrument, int256 baseAmount) internal returns (uint256) {
        if (baseAmount > 0) {
            return quoter.quoteExactInputSingle({
                tokenIn: address(instrument.base),
                tokenOut: address(instrument.quote),
                fee: instrument.uniswapFee,
                amountIn: uint256(baseAmount),
                sqrtPriceLimitX96: 0
            });
        } else {
            return quoter.quoteExactOutputSingle({
                tokenIn: address(instrument.quote),
                tokenOut: address(instrument.base),
                fee: instrument.uniswapFee,
                amountOut: uint256(-baseAmount),
                sqrtPriceLimitX96: 0
            });
        }
    }

    function fee(
        IContangoView contangoView,
        ContangoPositionNFT positionNFT,
        PositionId positionId,
        Symbol symbol,
        uint256 cost
    ) internal view returns (uint256) {
        address trader = PositionId.unwrap(positionId) == 0 ? msg.sender : positionNFT.positionOwner(positionId);
        IFeeModel feeModel = contangoView.feeModel(symbol);
        return address(feeModel) != address(0) ? feeModel.calculateFee(trader, positionId, cost) : 0;
    }
}

