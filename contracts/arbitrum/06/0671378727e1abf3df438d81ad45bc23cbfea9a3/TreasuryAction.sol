// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import {     Token,     PrimeRate,     PrimeCashFactors,     PrimeCashFactorsStorage,     RebalancingContextStorage } from "./Types.sol";
import {StorageLayoutV2} from "./StorageLayoutV2.sol";
import {LibStorage} from "./LibStorage.sol";
import {Constants} from "./Constants.sol";
import {SafeInt256} from "./SafeInt256.sol";
import {SafeUint256} from "./SafeUint256.sol";

import {Emitter} from "./Emitter.sol";
import {BalanceHandler} from "./BalanceHandler.sol";
import {PrimeRateLib} from "./PrimeRateLib.sol";
import {TokenHandler} from "./TokenHandler.sol";
import {nTokenHandler} from "./nTokenHandler.sol";
import {nTokenSupply} from "./nTokenSupply.sol";
import {PrimeCashExchangeRate, PrimeCashFactors} from "./PrimeCashExchangeRate.sol";
import {GenericToken} from "./GenericToken.sol";

import {ActionGuards} from "./ActionGuards.sol";
import {NotionalTreasury} from "./NotionalTreasury.sol";
import {Comptroller} from "./ComptrollerInterface.sol";
import {CErc20Interface} from "./CErc20Interface.sol";
import {IPrimeCashHoldingsOracle, DepositData, RedeemData} from "./IPrimeCashHoldingsOracle.sol";
import {IRebalancingStrategy, RebalancingData} from "./IRebalancingStrategy.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract TreasuryAction is StorageLayoutV2, ActionGuards, NotionalTreasury {
    using SafeUint256 for uint256;
    using SafeInt256 for int256;
    using SafeERC20 for IERC20;
    using TokenHandler for Token;

    IERC20 public immutable COMP;
    Comptroller public immutable COMPTROLLER;

    /// @dev Harvest methods are only callable by the authorized treasury manager contract
    modifier onlyManagerContract() {
        require(treasuryManagerContract == msg.sender, "Treasury manager required");
        _;
    }

    constructor(Comptroller _comptroller) {
        COMPTROLLER = _comptroller;
        COMP = address(_comptroller) == address(0) ? IERC20(address(0)) : IERC20(_comptroller.getCompAddress());
    }

    /// @notice Sets the new treasury manager contract
    function setTreasuryManager(address manager) external override onlyOwner {
        emit TreasuryManagerChanged(treasuryManagerContract, manager);
        treasuryManagerContract = manager;
    }

    /// @notice Sets the reserve buffer. This is the amount of reserve balance to keep denominated in 1e8
    /// The reserve cannot be harvested if it's below this amount. This portion of the reserve will remain on
    /// the contract to act as a buffer against potential insolvency.
    /// @param currencyId refers to the currency of the reserve
    /// @param bufferAmount reserve buffer amount to keep in internal token precision (1e8)
    function setReserveBuffer(uint16 currencyId, uint256 bufferAmount) external override onlyOwner {
        _checkValidCurrency(currencyId);
        reserveBuffer[currencyId] = bufferAmount;
        emit ReserveBufferUpdated(currencyId, bufferAmount);
    }

    /// @notice Updates the emission rate of incentives for a given currency
    /// @dev emit:UpdateIncentiveEmissionRate
    /// @param currencyId the currency id that the nToken references
    /// @param newEmissionRate Target total incentives to emit for an nToken over an entire year
    /// denominated in WHOLE TOKENS (i.e. setting this to 1 means 1e8 tokens). The rate will not be
    /// exact due to multiplier effects and fluctuating token supply.
    function updateIncentiveEmissionRate(uint16 currencyId, uint32 newEmissionRate)
        external
        override
        onlyOwner
    {
        _checkValidCurrency(currencyId);
        address nTokenAddress = nTokenHandler.nTokenAddress(currencyId);
        require(nTokenAddress != address(0));
        // Sanity check that emissions rate is not specified in 1e8 terms.
        require(newEmissionRate < Constants.INTERNAL_TOKEN_PRECISION, "Invalid rate");

        nTokenSupply.setIncentiveEmissionRate(nTokenAddress, newEmissionRate, block.timestamp);
        emit UpdateIncentiveEmissionRate(currencyId, newEmissionRate);
    }


    /// @notice This is used in the case of insolvency. It allows the owner to re-align the reserve with its correct balance.
    /// @param currencyId refers to the currency of the reserve
    /// @param newBalance new reserve balance to set, must be less than the current balance
    function setReserveCashBalance(uint16 currencyId, int256 newBalance)
        external
        override
        onlyOwner
    {
        _checkValidCurrency(currencyId);
        // newBalance cannot be negative and is checked inside BalanceHandler.setReserveCashBalance
        BalanceHandler.setReserveCashBalance(currencyId, newBalance);
    }

    /// @notice Claims COMP incentives earned and transfers to the treasury manager contract.
    /// @param cTokens a list of cTokens to claim incentives for
    /// @return the balance of COMP claimed
    function claimCOMPAndTransfer(address[] calldata cTokens)
        external
        override
        onlyManagerContract
        nonReentrant
        returns (uint256)
    {
        uint256 balanceBefore = COMP.balanceOf(address(this));
        COMPTROLLER.claimComp(address(this), cTokens);
        uint256 balanceAfter = COMP.balanceOf(address(this));

        // NOTE: the onlyManagerContract modifier prevents a transfer to address(0) here
        uint256 netBalance = balanceAfter.sub(balanceBefore);
        if (netBalance > 0) {
            COMP.safeTransfer(msg.sender, netBalance);
        }

        // NOTE: TreasuryManager contract will emit a COMPHarvested event
        return netBalance;
    }

    /// @notice redeems and transfers tokens to the treasury manager contract
    function _redeemAndTransfer(uint16 currencyId, int256 primeCashRedeemAmount) private returns (uint256) {
        PrimeRate memory primeRate = PrimeRateLib.buildPrimeRateStateful(currencyId);
        Emitter.emitTransferPrimeCash(Constants.FEE_RESERVE, treasuryManagerContract, currencyId, primeCashRedeemAmount);

        int256 actualTransferExternal = TokenHandler.withdrawPrimeCash(
            treasuryManagerContract,
            currencyId,
            primeCashRedeemAmount.neg(),
            primeRate,
            true // if ETH, transfers it as WETH
        ).neg();

        require(actualTransferExternal > 0);
        return uint256(actualTransferExternal);
    }

    /// @notice Transfers some amount of reserve assets to the treasury manager contract to be invested
    /// into the sNOTE pool.
    /// @param currencies an array of currencies to transfer from Notional
    function transferReserveToTreasury(uint16[] calldata currencies)
        external
        override
        onlyManagerContract
        nonReentrant
        returns (uint256[] memory)
    {
        uint256[] memory amountsTransferred = new uint256[](currencies.length);

        for (uint256 i; i < currencies.length; ++i) {
            // Prevents duplicate currency IDs
            if (i > 0) require(currencies[i] > currencies[i - 1], "IDs must be sorted");

            uint16 currencyId = currencies[i];

            _checkValidCurrency(currencyId);

            // Reserve buffer amount in INTERNAL_TOKEN_PRECISION
            int256 bufferInternal = SafeInt256.toInt(reserveBuffer[currencyId]);

            // Reserve requirement not defined
            if (bufferInternal == 0) continue;

            int256 reserveInternal = BalanceHandler.getPositiveCashBalance(Constants.FEE_RESERVE, currencyId);

            // Do not withdraw anything if reserve is below or equal to reserve requirement
            if (reserveInternal <= bufferInternal) continue;

            // Actual reserve amount allowed to be redeemed and transferred
            // NOTE: overflow not possible with the check above
            int256 primeCashRedeemed = reserveInternal - bufferInternal;

            // Redeems prime cash and transfer underlying to treasury manager contract
            amountsTransferred[i] = _redeemAndTransfer(currencyId, primeCashRedeemed);

            // Updates the reserve balance
            BalanceHandler.harvestExcessReserveBalance(
                currencyId,
                reserveInternal,
                primeCashRedeemed
            );
        }

        // NOTE: TreasuryManager contract will emit an AssetsHarvested event
        return amountsTransferred;
    }

    function setRebalancingTargets(uint16 currencyId, RebalancingTargetConfig[] calldata targets) external override onlyOwner {
        IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
        address[] memory holdings = oracle.holdings();

        require(targets.length == holdings.length);

        mapping(address => uint8) storage rebalancingTargets = LibStorage.getRebalancingTargets()[currencyId];
        uint256 totalPercentage;
        for (uint256 i; i < holdings.length; ++i) {
            RebalancingTargetConfig calldata config = targets[i];
            address holding = holdings[i];

            require(config.holding == holding);
            totalPercentage = totalPercentage.add(config.target);
            rebalancingTargets[holding] = config.target;
        }
        require(totalPercentage <= uint256(Constants.PERCENTAGE_DECIMALS));

        emit RebalancingTargetsUpdated(currencyId, targets);
    }

    function setRebalancingCooldown(uint16 currencyId, uint40 cooldownTimeInSeconds) external override onlyOwner {
        mapping(uint16 => RebalancingContextStorage) storage store = LibStorage.getRebalancingContext();
        store[currencyId].rebalancingCooldownInSeconds = cooldownTimeInSeconds;
        emit RebalancingCooldownUpdated(currencyId, cooldownTimeInSeconds);
    }

    function rebalance(uint16[] calldata currencyId) external override onlyManagerContract {
        for (uint256 i; i < currencyId.length; ++i) {
            _rebalanceCurrency(currencyId[i]);
        }
    }

    function _rebalanceCurrency(uint16 currencyId) private {
        RebalancingContextStorage memory context = LibStorage.getRebalancingContext()[currencyId];

        require(
            uint256(context.lastRebalanceTimestampInSeconds).add(context.rebalancingCooldownInSeconds) < block.timestamp, 
            "Rebalancing cooldown"
        );

        // Accrues interest up to the current block before any rebalancing is executed
        PrimeRate memory pr = PrimeRateLib.buildPrimeRateStateful(currencyId);

        _executeRebalance(currencyId);

        // if previous underlying scalar at rebalance == 0, then it is the first rebalance and
        // annualized interest rate will be left as zero. The previous underlying scalar will
        // be set to the new factors.underlyingScalar.
        uint256 annualizedInterestRate;
        uint256 supplyFactor = pr.supplyFactor.toUint();
        if (context.previousSupplyFactorAtRebalance != 0) {
            uint256 interestRate = supplyFactor
                .mul(Constants.SCALAR_PRECISION)
                .div(context.previousSupplyFactorAtRebalance)
                .sub(Constants.SCALAR_PRECISION) 
                .div(uint256(Constants.RATE_PRECISION));

            annualizedInterestRate = interestRate
                .mul(Constants.YEAR)
                .div(block.timestamp.sub(context.lastRebalanceTimestampInSeconds));
        }

        _saveRebalancingContext(currencyId, supplyFactor.toUint128());
        _saveOracleSupplyRate(currencyId, annualizedInterestRate);

        emit CurrencyRebalanced(currencyId, supplyFactor, annualizedInterestRate);
    }

    function _saveOracleSupplyRate(uint16 currencyId, uint256 annualizedInterestRate) private {
        mapping(uint256 => PrimeCashFactorsStorage) storage store = LibStorage.getPrimeCashFactors();
        store[currencyId].oracleSupplyRate = annualizedInterestRate.toUint32();
    }

    function _saveRebalancingContext(uint16 currencyId, uint128 supplyFactor) private {
        mapping(uint16 => RebalancingContextStorage) storage store = LibStorage.getRebalancingContext();
        store[currencyId].lastRebalanceTimestampInSeconds = block.timestamp.toUint40();
        store[currencyId].previousSupplyFactorAtRebalance = supplyFactor;
    }

    function _getRebalancingTargets(uint16 currencyId, address[] memory holdings) private view returns (uint8[] memory targets) {
        mapping(address => uint8) storage rebalancingTargets = LibStorage.getRebalancingTargets()[currencyId];
        targets = new uint8[](holdings.length);
        uint256 totalPercentage;
        for (uint256 i; i < holdings.length; ++i) {
            uint8 target = rebalancingTargets[holdings[i]];
            targets[i] = target;
            totalPercentage = totalPercentage.add(target);
        }
        require(totalPercentage <= uint256(Constants.PERCENTAGE_DECIMALS));
    }

    function _executeRebalance(uint16 currencyId) private {
        IPrimeCashHoldingsOracle oracle = PrimeCashExchangeRate.getPrimeCashHoldingsOracle(currencyId);
        address[] memory holdings = oracle.holdings();
        uint8[] memory rebalancingTargets = _getRebalancingTargets(currencyId, holdings);
        RebalancingData memory data = _calculateRebalance(oracle, holdings, rebalancingTargets);

        (uint256 totalUnderlyingValueBefore, /* */) = oracle.getTotalUnderlyingValueStateful();

        // Process redemptions first
        Token memory underlyingToken = TokenHandler.getUnderlyingToken(currencyId);
        (bool hasFailure, /* */) = TokenHandler.executeMoneyMarketRedemptions(underlyingToken, data.redeemData);

        if (!hasFailure) {
            // Process deposits only if redemptions were successful
            _executeDeposits(underlyingToken, data.depositData);
        }

        (uint256 totalUnderlyingValueAfter, /* */) = oracle.getTotalUnderlyingValueStateful();

        int256 underlyingDelta = totalUnderlyingValueBefore.toInt().sub(totalUnderlyingValueAfter.toInt());
        int256 percentChange = underlyingDelta.abs().mul(Constants.RATE_PRECISION)
            .div(totalUnderlyingValueBefore.toInt());
        require(percentChange < Constants.REBALANCING_UNDERLYING_DELTA_PERCENT);
    }

    function _executeDeposits(Token memory underlyingToken, DepositData[] memory deposits) private {
        uint256 totalUnderlyingDepositAmount;
        
        for (uint256 i; i < deposits.length; i++) {
            DepositData memory depositData = deposits[i];
            // Measure the token balance change if the `assetToken` value is set in the
            // current deposit data struct. 
            uint256 oldAssetBalance = IERC20(depositData.assetToken).balanceOf(address(this));

            // Measure the underlying balance change before and after the call.
            uint256 oldUnderlyingBalance = underlyingToken.balanceOf(address(this));

            for (uint256 j; j < depositData.targets.length; ++j) {
                GenericToken.executeLowLevelCall(
                    depositData.targets[j], 
                    depositData.msgValue[j], 
                    depositData.callData[j],
                    true // Allow low level calls to revert
                );
            }

            // Ensure that the underlying balance change matches the deposit amount
            uint256 newUnderlyingBalance = underlyingToken.balanceOf(address(this));
            uint256 underlyingBalanceChange = oldUnderlyingBalance.sub(newUnderlyingBalance);
            // If the call is not the final deposit, then underlyingDepositAmount should
            // be set to zero.
            require(underlyingBalanceChange <= depositData.underlyingDepositAmount);
        
            // Measure and update the asset token
            uint256 newAssetBalance = IERC20(depositData.assetToken).balanceOf(address(this));
            require(oldAssetBalance <= newAssetBalance);
            TokenHandler.updateStoredTokenBalance(depositData.assetToken, oldAssetBalance, newAssetBalance);

            // Update the total value with the net change
            totalUnderlyingDepositAmount = totalUnderlyingDepositAmount.add(underlyingBalanceChange);

            // totalUnderlyingDepositAmount needs to be subtracted from the underlying balance because
            // we are trading underlying cash for asset cash
            TokenHandler.updateStoredTokenBalance(underlyingToken.tokenAddress, oldUnderlyingBalance, newUnderlyingBalance);
        }
    }

    function _calculateRebalance(
        IPrimeCashHoldingsOracle oracle,
        address[] memory holdings,
        uint8[] memory rebalancingTargets
    ) private view returns (RebalancingData memory rebalancingData) {
        uint256[] memory values = oracle.holdingValuesInUnderlying();

        (
            uint256 totalValue,
            /* uint256 internalPrecision */
        ) = oracle.getTotalUnderlyingValueView();

        address[] memory redeemHoldings = new address[](holdings.length);
        uint256[] memory redeemAmounts = new uint256[](holdings.length);
        address[] memory depositHoldings = new address[](holdings.length);
        uint256[] memory depositAmounts = new uint256[](holdings.length);

        for (uint256 i; i < holdings.length; i++) {
            address holding = holdings[i];
            uint256 targetAmount = totalValue.mul(rebalancingTargets[i]).div(
                uint256(Constants.PERCENTAGE_DECIMALS)
            );
            uint256 currentAmount = values[i];

            redeemHoldings[i] = holding;
            depositHoldings[i] = holding;

            if (targetAmount < currentAmount) {
                redeemAmounts[i] = currentAmount - targetAmount;
            } else if (currentAmount < targetAmount) {
                depositAmounts[i] = targetAmount - currentAmount;
            }
        }

        rebalancingData.redeemData = oracle.getRedemptionCalldataForRebalancing(redeemHoldings, redeemAmounts);
        rebalancingData.depositData = oracle.getDepositCalldataForRebalancing(depositHoldings, depositAmounts);
    }
}

