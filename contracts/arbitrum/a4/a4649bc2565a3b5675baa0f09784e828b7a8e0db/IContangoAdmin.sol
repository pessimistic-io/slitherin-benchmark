//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IERC20Metadata as IERC20} from "./IERC20Metadata.sol";
import "./IERC7399.sol";

import "./DataTypes.sol";
import "./IMoneyMarket.sol";
import "./IFeeModel.sol";
import "./IReferralManager.sol";

interface IContangoAdminEvents {
    event ClosingOnlySet(Symbol indexed symbol, bool closingOnly);
    event DexRegistered(Dex indexed dex, address spender, address router);
    event FlashLoanProviderRegistered(FlashLoanProvider indexed id, IERC7399 provider);
    event InstrumentCreated(Symbol indexed symbol, IERC20 base, IERC20 quote);
    event MoneyMarketRegistered(MoneyMarket indexed id, IMoneyMarket moneyMarket);
    event RemainingQuoteToleranceSet(uint256 remainingQuoteTolerance);
}

interface IContangoAdmin is IContangoAdminEvents {
    error InstrumentAlreadyExists(Symbol symbol);

    function createInstrument(Symbol symbol, IERC20 base, IERC20 quote) external;

    function registerDex(Dex dex, address spender, address router) external;

    function registerFlashLoanProvider(FlashLoanProvider id, IERC7399 provider) external;

    function setRemainingQuoteTolerance(uint256 treasury) external;

    function setClosingOnly(Symbol symbol, bool closingOnly) external;

    function pause() external;

    function unpause() external;
}

