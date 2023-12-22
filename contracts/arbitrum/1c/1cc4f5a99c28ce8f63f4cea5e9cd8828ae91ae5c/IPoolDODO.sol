//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IPoolDODO {
    // function _QUOTE_TOKEN_() external view returns (address);

    // function _BASE_TOKEN_() external view returns (address);

    function _BASE_PRICE_CUMULATIVE_LAST_() external view returns (uint256);

    function _BASE_RESERVE_() external view returns (uint112);

    function _BASE_TARGET_() external view returns (uint112);

    // function _BASE_TOKEN_() external view returns (address);

    function _BLOCK_TIMESTAMP_LAST_() external view returns (uint32);

    function _IS_OPEN_TWAP_() external view returns (bool);

    function _I_() external view returns (uint128);

    // function _K_() external view returns (uint64);

    // function _LP_FEE_RATE_() external view returns (uint64);

    // function _MAINTAINER_() external view returns (address);

    function _MT_FEE_RATE_MODEL_() external view returns (address);

    // function _NEW_OWNER_() external view returns (address);
    //
    // function _OWNER_() external view returns (address);

    function _QUOTE_RESERVE_() external view returns (uint112);

    function _QUOTE_TARGET_() external view returns (uint112);

    // function _QUOTE_TOKEN_() external view returns (address);

    function _RState_() external view returns (uint32);

    // function claimOwnership() external;

    //   function flashLoan ( uint256 baseAmount, uint256 quoteAmount, address assetTo, bytes data ) external;
    function getBaseInput() external view returns (uint256 input);

    function getMidPrice() external view returns (uint256 midPrice);

    //   function getPMMState (  ) external view returns ( tuple state );
    function getPMMStateForCall()
        external
        view
        returns (
            uint256 i,
            uint256 K,
            uint256 B,
            uint256 Q,
            uint256 B0,
            uint256 Q0,
            uint256 R
        );

    function getQuoteInput() external view returns (uint256 input);

    function getUserFeeRate(
        address user
    ) external view returns (uint256 lpFeeRate, uint256 mtFeeRate);

    function getVaultReserve()
        external
        view
        returns (uint256 baseReserve, uint256 quoteReserve);

    function init(
        address owner,
        address maintainer,
        address baseTokenAddress,
        address quoteTokenAddress,
        uint256 lpFeeRate,
        address mtFeeRateModel,
        uint256 k,
        uint256 i,
        bool isOpenTWAP
    ) external;

    function initOwner(address newOwner) external;

    function querySellBase(
        address trader,
        uint256 payBaseAmount
    )
        external
        view
        returns (
            uint256 receiveQuoteAmount,
            uint256 mtFee,
            uint8 newRState,
            uint256 newBaseTarget
        );

    function querySellQuote(
        address trader,
        uint256 payQuoteAmount
    )
        external
        view
        returns (
            uint256 receiveBaseAmount,
            uint256 mtFee,
            uint8 newRState,
            uint256 newQuoteTarget
        );

    function ratioSync() external;

    function reset(
        address assetTo,
        uint256 newLpFeeRate,
        uint256 newI,
        uint256 newK,
        uint256 baseOutAmount,
        uint256 quoteOutAmount,
        uint256 minBaseReserve,
        uint256 minQuoteReserve
    ) external returns (bool);

    function retrieve(address to, address token, uint256 amount) external;

    function sellBase(address to) external returns (uint256 receiveQuoteAmount);

    function sellQuote(address to) external returns (uint256 receiveBaseAmount);

    function _BASE_BALANCE_() external view returns (uint256);

    function _BASE_BALANCE_LIMIT_() external view returns (uint256);

    function _BASE_CAPITAL_RECEIVE_QUOTE_() external view returns (uint256);

    function _BASE_CAPITAL_TOKEN_() external view returns (address);

    function _BASE_TOKEN_() external view returns (address);

    function _BUYING_ALLOWED_() external view returns (bool);

    function _CLAIMED_(address) external view returns (bool);

    function _CLOSED_() external view returns (bool);

    function _DEPOSIT_BASE_ALLOWED_() external view returns (bool);

    function _DEPOSIT_QUOTE_ALLOWED_() external view returns (bool);

    function _GAS_PRICE_LIMIT_() external view returns (uint256);

    function _K_() external view returns (uint256);

    function _LP_FEE_RATE_() external view returns (uint256);

    function _MAINTAINER_() external view returns (address);

    function _MT_FEE_RATE_() external view returns (uint256);

    function _NEW_OWNER_() external view returns (address);

    function _ORACLE_() external view returns (address);

    function _OWNER_() external view returns (address);

    function _QUOTE_BALANCE_() external view returns (uint256);

    function _QUOTE_BALANCE_LIMIT_() external view returns (uint256);

    function _QUOTE_CAPITAL_RECEIVE_BASE_() external view returns (uint256);

    function _QUOTE_CAPITAL_TOKEN_() external view returns (address);

    function _QUOTE_TOKEN_() external view returns (address);

    function _R_STATUS_() external view returns (uint8);

    function _SELLING_ALLOWED_() external view returns (bool);

    function _SUPERVISOR_() external view returns (address);

    function _TARGET_BASE_TOKEN_AMOUNT_() external view returns (uint256);

    function _TARGET_QUOTE_TOKEN_AMOUNT_() external view returns (uint256);

    function _TRADE_ALLOWED_() external view returns (bool);

    function buyBaseToken(
        uint256 amount,
        uint256 maxPayQuote,
        bytes memory data
    ) external returns (uint256);

    function claimAssets() external;

    function claimOwnership() external;

    function depositBase(uint256 amount) external returns (uint256);

    function depositBaseTo(
        address to,
        uint256 amount
    ) external returns (uint256);

    function depositQuote(uint256 amount) external returns (uint256);

    function depositQuoteTo(
        address to,
        uint256 amount
    ) external returns (uint256);

    function disableBaseDeposit() external;

    function disableBuying() external;

    function disableQuoteDeposit() external;

    function disableSelling() external;

    function disableTrading() external;

    function donateBaseToken(uint256 amount) external;

    function donateQuoteToken(uint256 amount) external;

    function enableBaseDeposit() external;

    function enableBuying() external;

    function enableQuoteDeposit() external;

    function enableSelling() external;

    function enableTrading() external;

    function finalSettlement() external;

    function getBaseCapitalBalanceOf(
        address lp
    ) external view returns (uint256);

    function getExpectedTarget()
        external
        view
        returns (uint256 baseTarget, uint256 quoteTarget);

    function getLpBaseBalance(
        address lp
    ) external view returns (uint256 lpBalance);

    function getLpQuoteBalance(
        address lp
    ) external view returns (uint256 lpBalance);

    // function getMidPrice() external view returns (uint256 midPrice);

    function getOraclePrice() external view returns (uint256);

    function getQuoteCapitalBalanceOf(
        address lp
    ) external view returns (uint256);

    function getTotalBaseCapital() external view returns (uint256);

    function getTotalQuoteCapital() external view returns (uint256);

    function getWithdrawBasePenalty(
        uint256 amount
    ) external view returns (uint256 penalty);

    function getWithdrawQuotePenalty(
        uint256 amount
    ) external view returns (uint256 penalty);

    function init(
        address owner,
        address supervisor,
        address maintainer,
        address baseToken,
        address quoteToken,
        address oracle,
        uint256 lpFeeRate,
        uint256 mtFeeRate,
        uint256 k,
        uint256 gasPriceLimit
    ) external;

    function queryBuyBaseToken(
        uint256 amount
    ) external view returns (uint256 payQuote);

    function querySellBaseToken(
        uint256 amount
    ) external view returns (uint256 receiveQuote);

    function retrieve(address token, uint256 amount) external;

    function sellBaseToken(
        uint256 amount,
        uint256 minReceiveQuote,
        bytes memory data
    ) external returns (uint256);

    function setBaseBalanceLimit(uint256 newBaseBalanceLimit) external;

    function setGasPriceLimit(uint256 newGasPriceLimit) external;

    function setK(uint256 newK) external;

    function setLiquidityProviderFeeRate(
        uint256 newLiquidityPorviderFeeRate
    ) external;

    function setMaintainer(address newMaintainer) external;

    function setMaintainerFeeRate(uint256 newMaintainerFeeRate) external;

    function setOracle(address newOracle) external;

    function setQuoteBalanceLimit(uint256 newQuoteBalanceLimit) external;

    function setSupervisor(address newSupervisor) external;

    function transferOwnership(address newOwner) external;

    // function version() external pure returns (uint256);

    function version() external pure returns (string memory);

    function withdrawAllBase() external returns (uint256);

    function withdrawAllBaseTo(address to) external returns (uint256);

    function withdrawAllQuote() external returns (uint256);

    function withdrawAllQuoteTo(address to) external returns (uint256);

    function withdrawBase(uint256 amount) external returns (uint256);

    function withdrawBaseTo(
        address to,
        uint256 amount
    ) external returns (uint256);

    function withdrawQuote(uint256 amount) external returns (uint256);

    function withdrawQuoteTo(
        address to,
        uint256 amount
    ) external returns (uint256);
}

