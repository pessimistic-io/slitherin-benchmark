//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DataTypes} from "./libraries_DataTypes.sol";
import {ICauldron} from "./ICauldron.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {IPoolOracle} from "./IPoolOracle.sol";

import "./IContangoOracle.sol";
import "./Errors.sol";
import "./Uniswap.sol";
import "./ContangoYield.sol";

contract ContangoYieldOracle is IContangoOracle {
    using YieldUtils for *;
    using PoolAddress for address;
    using SafeCast for *;

    ContangoYield public immutable contangoYield;
    ICauldron public immutable cauldron;
    IPoolOracle public immutable oracle;

    constructor(ContangoYield _contangoYield, ICauldron _cauldron, IPoolOracle _oracle) {
        contangoYield = _contangoYield;
        cauldron = _cauldron;
        oracle = _oracle;
    }

    function closingCost(PositionId positionId, uint24 uniswapFee, uint32 uniswapPeriod)
        external
        override
        returns (uint256 cost)
    {
        YieldInstrument memory instrument = _validatePosition(positionId);
        DataTypes.Balances memory balances = cauldron.balances(positionId.toVaultId());

        (uint256 inkPV,) = oracle.getSellFYTokenPreview(instrument.basePool, balances.ink);

        address pool = UniswapV3Handler.UNISWAP_FACTORY.computeAddress(
            PoolAddress.getPoolKey(address(instrument.base), address(instrument.quote), uniswapFee)
        );

        uint256 hedgeCost = OracleLibrary.getQuoteAtTick({
            tick: OracleLibrary.consult(pool, uniswapPeriod),
            baseAmount: inkPV.toUint128(),
            baseToken: address(instrument.base),
            quoteToken: address(instrument.quote)
        });

        (uint256 artPV,) = oracle.getBuyFYTokenPreview(instrument.quotePool, balances.art);

        cost = hedgeCost + balances.art - artPV;
    }

    function _validatePosition(PositionId positionId) private view returns (YieldInstrument memory instrument) {
        Position memory position = contangoYield.position(positionId);
        if (position.openQuantity == 0 && position.openCost == 0) {
            if (position.collateral <= 0) {
                revert InvalidPosition(positionId);
            }
        }
        instrument = contangoYield.yieldInstrumentV2(position.symbol);
    }
}

