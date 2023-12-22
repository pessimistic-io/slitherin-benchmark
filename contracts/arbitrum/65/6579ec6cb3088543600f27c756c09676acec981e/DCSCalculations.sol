// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Math } from "./Math.sol";

import { Deposit, OptionBarrierType, OptionBarrier, VaultStatus, Withdrawal } from "./Structs.sol";
import { IOracle } from "./IOracle.sol";
import { ICegaState } from "./ICegaState.sol";
import { DCSVault } from "./DCSVault.sol";

library DCSCalculations {
    uint256 public constant DAYS_IN_YEAR = 365;
    uint256 public constant SECONDS_TO_DAYS = 86400;
    uint256 public constant BPS_DECIMALS = 10 ** 4;
    uint256 public constant LARGE_CONSTANT = 10 ** 18;
    uint256 public constant ORACLE_STALE_DELAY = 1 days;

    function convertBaseAssetToAlternativeAsset(
        uint256 priceToConvert,
        uint256 strikePrice
    ) public pure returns (uint256) {
        return (priceToConvert * LARGE_CONSTANT) / (strikePrice * LARGE_CONSTANT);
    }

    function getSpotPriceAtExpiry(
        string memory oracleName,
        uint256 tradeEndDate,
        address cegaStateAddress
    ) public view returns (uint256) {
        ICegaState cegaState = ICegaState(cegaStateAddress);
        address oracle = cegaState.oracleAddresses(oracleName);
        require(oracle != address(0), "400:Unregistered");

        // TODO need to use historical data
        (, int256 answer, uint256 startedAt, , ) = IOracle(oracle).latestRoundData();
        require(tradeEndDate - ORACLE_STALE_DELAY <= startedAt, "400:T");
        return uint256(answer);
    }

    /**
     * @notice Calculates the fees that should be collected from a given vault
     * @param vaultFinalPayoff is the final payoff of the vault
     * @param feeBps is the fee in bps
     */
    function calculateFees(uint256 vaultFinalPayoff, uint256 feeBps) public pure returns (uint256) {
        uint256 totalFee = (vaultFinalPayoff * feeBps) / BPS_DECIMALS;
        return totalFee;
    }

    /**
     * @notice Calculates the coupon payment accumulated for a given number of daysPassed
     * @param underlyingAmount is the amount of assets
     * @param aprBps is the apr in bps
     * @param tradeDate is the date of the trade
     */
    function calculateCouponPayment(
        uint256 underlyingAmount,
        uint256 aprBps,
        uint256 tradeDate,
        uint256 tenorInDays
    ) public view returns (uint256) {
        uint256 currentTime = block.timestamp;

        // if (currentTime > tradeExpiry) {
        //     self.vaultStatus = VaultStatus.TradeExpired;
        //     return;
        // }

        uint256 daysPassed = (currentTime - tradeDate) / DCSCalculations.SECONDS_TO_DAYS;
        uint256 couponDays = Math.min(daysPassed, tenorInDays);

        return (underlyingAmount * couponDays * aprBps * LARGE_CONSTANT) / DAYS_IN_YEAR / BPS_DECIMALS / LARGE_CONSTANT;
    }
}

