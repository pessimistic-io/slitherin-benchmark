//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {DataTypes} from "./libraries_DataTypes.sol";
import {IContangoLadle} from "./IContangoLadle.sol";
import {ICauldron} from "./ICauldron.sol";

import "./libraries_DataTypes.sol";

interface IContangoYieldAdminEvents {
    event YieldInstrumentCreatedV2(
        Symbol symbol,
        uint32 maturity,
        bytes6 baseId,
        ERC20 base,
        IFYToken baseFyToken,
        IPool basePool,
        bytes6 quoteId,
        ERC20 quote,
        IFYToken quoteFyToken,
        IPool quotePool
    );
    event LadleSet(IContangoLadle ladle);
    event CauldronSet(ICauldron cauldron);
}

interface IContangoYieldAdmin is IContangoYieldAdminEvents {
    error InvalidBaseId(Symbol symbol, bytes6 baseId);
    error InvalidQuoteId(Symbol symbol, bytes6 quoteId);
    error MismatchedMaturity(Symbol symbol, bytes6 baseId, uint256 baseMaturity, bytes6 quoteId, uint256 quoteMaturity);

    function createYieldInstrumentV2(Symbol symbol, bytes6 baseId, bytes6 quoteId, IFeeModel feeModel)
        external
        returns (YieldInstrument memory instrument);
}

