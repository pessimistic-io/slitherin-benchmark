// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IUniswapV3Pool.sol";
import "./PositionKey.sol";
import "./FixedPoint96.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import "./TickMath.sol";
import "./SafeCastLib.sol";
import "./SafeCast.sol";
import "./DataType.sol";
import "./ScaledAsset.sol";
import "./InterestRateModel.sol";
import "./Constants.sol";
import "./UniHelper.sol";
import "./LPMath.sol";
import "./Math.sol";
import "./Reallocation.sol";

/*
 * Error Codes
 * P1: There is no enough SQRT liquidity.
 * P2: Out of range
 */
library Perp {
    using ScaledAsset for ScaledAsset.TokenStatus;
    using SafeCastLib for uint256;
    using Math for int256;

    struct PositionStatus {
        int256 amount;
        int256 entryValue;
    }

    struct SqrtPositionStatus {
        int256 amount;
        int256 entryValue;
        int256 stableRebalanceEntryValue;
        int256 underlyingRebalanceEntryValue;
        uint256 entryTradeFee0;
        uint256 entryTradeFee1;
        uint256 entryPremium;
    }

    struct UpdatePerpParams {
        int256 tradeAmount;
        int256 stableAmount;
    }

    struct UpdateSqrtPerpParams {
        int256 tradeSqrtAmount;
        int256 stableAmount;
    }

    struct Payoff {
        int256 perpEntryUpdate;
        int256 sqrtEntryUpdate;
        int256 sqrtRebalanceEntryUpdateUnderlying;
        int256 sqrtRebalanceEntryUpdateStable;
        int256 perpPayoff;
        int256 sqrtPayoff;
    }

    struct SqrtPerpAssetStatus {
        // if it is stable then uniswapPool is address(0)
        address uniswapPool;
        int24 tickLower;
        int24 tickUpper;
        uint256 totalAmount;
        uint256 borrowedAmount;
        uint256 supplyPremiumGrowth;
        uint256 borrowPremiumGrowth;
        uint256 fee0Growth;
        uint256 fee1Growth;
        ScaledAsset.UserStatus rebalancePositionUnderlying;
        ScaledAsset.UserStatus rebalancePositionStable;
        int256 rebalanceFeeGrowthUnderlying;
        int256 rebalanceFeeGrowthStable;
    }

    struct UserStatus {
        PositionStatus perp;
        SqrtPositionStatus sqrtPerp;
        ScaledAsset.UserStatus underlying;
        ScaledAsset.UserStatus stable;
        int24 rebalanceLastTickLower;
        int24 rebalanceLastTickUpper;
        int256 rebalanceEntryFeeUnderlying;
        int256 rebalanceEntryFeeStable;
    }

    event Rebalanced(uint256 assetId, int24 tickLower, int24 tickUpper, int256 profit);

    function createAssetStatus(address uniswapPool, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (SqrtPerpAssetStatus memory)
    {
        return SqrtPerpAssetStatus(
            uniswapPool,
            tickLower,
            tickUpper,
            0,
            0,
            0,
            0,
            0,
            0,
            ScaledAsset.createUserStatus(),
            ScaledAsset.createUserStatus(),
            0,
            0
        );
    }

    function createPerpUserStatus() internal pure returns (UserStatus memory) {
        return UserStatus(
            PositionStatus(0, 0),
            SqrtPositionStatus(0, 0, 0, 0, 0, 0, 0),
            ScaledAsset.createUserStatus(),
            ScaledAsset.createUserStatus(),
            0,
            0,
            0,
            0
        );
    }

    function updateRebalanceFeeGrowth(
        DataType.AssetStatus memory _assetStatusUnderlying,
        ScaledAsset.TokenStatus memory _assetStatusStable,
        SqrtPerpAssetStatus storage _sqrtAssetStatus
    ) internal {
        // settle fee for rebalance position
        if (_sqrtAssetStatus.totalAmount > 0) {
            _sqrtAssetStatus.rebalanceFeeGrowthUnderlying += _assetStatusUnderlying.tokenStatus.settleUserFee(
                _sqrtAssetStatus.rebalancePositionUnderlying
            ) * 1e18 / int256(_sqrtAssetStatus.totalAmount);

            _sqrtAssetStatus.rebalanceFeeGrowthStable += _assetStatusStable.settleUserFee(
                _sqrtAssetStatus.rebalancePositionStable
            ) * 1e18 / int256(_sqrtAssetStatus.totalAmount);
        }
    }

    /**
     * @notice Reallocates LP position to be in range.
     * In case of in-range
     *   token0
     *     1/sqrt(x) - 1/sqrt(b1) -> 1/sqrt(x) - 1/sqrt(b2)
     *       1/sqrt(b2) - 1/sqrt(b1)
     *   token1
     *     sqrt(x) - sqrt(a1) -> sqrt(x) - sqrt(a2)
     *       sqrt(a2) - sqrt(a1)
     *
     * In case of out-of-range (tick high b1 < x)
     *   token0
     *     0 -> 1/sqrt(x) - 1/sqrt(b2)
     *       1/sqrt(b2) - 1/sqrt(x)
     *   token1
     *     sqrt(b1) - sqrt(a1) -> sqrt(x) - sqrt(a2)
     *       sqrt(b1) - sqrt(a1) - (sqrt(x) - sqrt(a2))
     *
     * In case of out-of-range (tick low x < a1)
     *   token0
     *     1/sqrt(a1) - 1/sqrt(b1) -> 1/sqrt(x) - 1/sqrt(b2)
     *       1/sqrt(a1) - 1/sqrt(b1) - (1/sqrt(x) - 1/sqrt(b2))
     *   token1
     *     0 -> sqrt(x) - sqrt(a2)
     *       sqrt(a2) - sqrt(x)
     */
    function reallocate(
        DataType.AssetStatus storage _assetStatusUnderlying,
        ScaledAsset.TokenStatus storage _assetStatusStable,
        SqrtPerpAssetStatus storage _sqrtAssetStatus,
        bool _enableRevert
    ) internal returns (bool, int256 profit) {
        updateRebalanceFeeGrowth(_assetStatusUnderlying, _assetStatusStable, _sqrtAssetStatus);

        (uint160 currentSqrtPrice, int24 currentTick,,,,,) = IUniswapV3Pool(_sqrtAssetStatus.uniswapPool).slot0();

        if (
            _sqrtAssetStatus.tickLower + _assetStatusUnderlying.riskParams.rebalanceThreshold < currentTick
                && currentTick < _sqrtAssetStatus.tickUpper - _assetStatusUnderlying.riskParams.rebalanceThreshold
        ) {
            return (false, 0);
        }

        uint128 totalLiquidityAmount = getAvailableLiquidityAmount(
            address(this), _sqrtAssetStatus.uniswapPool, _sqrtAssetStatus.tickLower, _sqrtAssetStatus.tickUpper
        );

        if (totalLiquidityAmount == 0) {
            (_sqrtAssetStatus.tickLower, _sqrtAssetStatus.tickUpper) =
                Reallocation.getNewRange(_assetStatusUnderlying, _assetStatusStable, currentTick);
            return (false, 0);
        }

        int24 tick;
        bool isOutOfRange;

        if (currentTick < _sqrtAssetStatus.tickLower) {
            // lower out
            isOutOfRange = true;
            tick = _sqrtAssetStatus.tickLower;
        } else if (currentTick < _sqrtAssetStatus.tickUpper) {
            // in range
            isOutOfRange = false;
        } else {
            // upper out
            isOutOfRange = true;
            tick = _sqrtAssetStatus.tickUpper;
        }

        rebalanceForInRange(
            _assetStatusUnderlying, _assetStatusStable, _sqrtAssetStatus, currentTick, totalLiquidityAmount
        );

        if (isOutOfRange) {
            profit = swapForOutOfRange(
                _assetStatusUnderlying,
                _assetStatusStable,
                _sqrtAssetStatus,
                currentSqrtPrice,
                tick,
                totalLiquidityAmount
            );

            require(!_enableRevert || profit >= 0, "CANTREBAL");

            if (profit > 0) {
                _sqrtAssetStatus.fee1Growth += uint256(profit) * Constants.ONE / _sqrtAssetStatus.totalAmount;
            }
        }

        emit Rebalanced(_assetStatusUnderlying.id, _sqrtAssetStatus.tickLower, _sqrtAssetStatus.tickUpper, profit);

        return (true, profit);
    }

    function rebalanceForInRange(
        DataType.AssetStatus storage _assetStatusUnderlying,
        ScaledAsset.TokenStatus storage _assetStatusStable,
        SqrtPerpAssetStatus storage _sqrtAssetStatus,
        int24 _currentTick,
        uint128 _totalLiquidityAmount
    ) internal {
        (uint256 receivedAmount0, uint256 receivedAmount1) = IUniswapV3Pool(_sqrtAssetStatus.uniswapPool).burn(
            _sqrtAssetStatus.tickLower, _sqrtAssetStatus.tickUpper, _totalLiquidityAmount
        );

        IUniswapV3Pool(_sqrtAssetStatus.uniswapPool).collect(
            address(this),
            _sqrtAssetStatus.tickLower,
            _sqrtAssetStatus.tickUpper,
            receivedAmount0.safeCastTo128(),
            receivedAmount1.safeCastTo128()
        );

        (_sqrtAssetStatus.tickLower, _sqrtAssetStatus.tickUpper) =
            Reallocation.getNewRange(_assetStatusUnderlying, _assetStatusStable, _currentTick);

        (uint256 requiredAmount0, uint256 requiredAmount1) = IUniswapV3Pool(_sqrtAssetStatus.uniswapPool).mint(
            address(this), _sqrtAssetStatus.tickLower, _sqrtAssetStatus.tickUpper, _totalLiquidityAmount, ""
        );

        updateRebalancePosition(
            _assetStatusUnderlying,
            _assetStatusStable,
            int256(receivedAmount0) - int256(requiredAmount0),
            int256(receivedAmount1) - int256(requiredAmount1)
        );
    }

    /**
     * @notice Swaps additional token amounts for rebalance.
     * In case of out-of-range (tick high b1 < x)
     *   token0
     *       1/sqrt(x)　- 1/sqrt(b1)
     *   token1
     *       sqrt(x) - sqrt(b1)
     *
     * In case of out-of-range (tick low x < a1)
     *   token0
     *       1/sqrt(x) - 1/sqrt(a1)
     *   token1
     *       sqrt(x) - sqrt(a1)
     */
    function swapForOutOfRange(
        DataType.AssetStatus storage _assetStatusUnderlying,
        ScaledAsset.TokenStatus storage _assetStatusStable,
        SqrtPerpAssetStatus storage _sqrtAssetStatus,
        uint160 _currentSqrtPrice,
        int24 _tick,
        uint128 _totalLiquidityAmount
    ) internal returns (int256 profit) {
        uint160 tickSqrtPrice = TickMath.getSqrtRatioAtTick(_tick);

        // 1/_currentSqrtPrice - 1/tickSqrtPrice
        int256 deltaPosition0 =
            LPMath.calculateAmount0ForLiquidity(_currentSqrtPrice, tickSqrtPrice, _totalLiquidityAmount, true);

        // _currentSqrtPrice - tickSqrtPrice
        int256 deltaPosition1 =
            LPMath.calculateAmount1ForLiquidity(_currentSqrtPrice, tickSqrtPrice, _totalLiquidityAmount, true);

        (, int256 amount1) = IUniswapV3Pool(_sqrtAssetStatus.uniswapPool).swap(
            address(this),
            // if x < lower then swap token0 for token1, if upper < x then swap token1 for token0.
            deltaPosition0 < 0,
            // + means exactIn, - means exactOut
            -deltaPosition0,
            (deltaPosition0 < 0 ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            ""
        );

        profit = -amount1 - deltaPosition1;

        updateRebalancePosition(_assetStatusUnderlying, _assetStatusStable, deltaPosition0, deltaPosition1);
    }

    function getAvailableLiquidityAmount(
        address _controllerAddress,
        address _uniswapPool,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns (uint128) {
        bytes32 positionKey = PositionKey.compute(_controllerAddress, _tickLower, _tickUpper);

        (uint128 liquidity,,,,) = IUniswapV3Pool(_uniswapPool).positions(positionKey);

        return liquidity;
    }

    function settleUserBalance(
        DataType.AssetStatus storage _underlyingAssetStatus,
        ScaledAsset.TokenStatus storage _stableAssetStatus,
        UserStatus storage _userStatus
    ) internal returns (bool) {
        (int256 deltaPositionUnderlying, int256 deltaPositionStable) = updateRebalanceEntry(
            _underlyingAssetStatus.sqrtAssetStatus, _userStatus, _underlyingAssetStatus.isMarginZero
        );

        if (deltaPositionUnderlying == 0 && deltaPositionStable == 0) {
            return false;
        }

        _userStatus.sqrtPerp.underlyingRebalanceEntryValue += deltaPositionUnderlying;
        _userStatus.sqrtPerp.stableRebalanceEntryValue += deltaPositionStable;

        // already settled fee

        _underlyingAssetStatus.tokenStatus.updatePosition(
            _underlyingAssetStatus.sqrtAssetStatus.rebalancePositionUnderlying, -deltaPositionUnderlying
        );
        _stableAssetStatus.updatePosition(
            _underlyingAssetStatus.sqrtAssetStatus.rebalancePositionStable, -deltaPositionStable
        );

        _underlyingAssetStatus.tokenStatus.updatePosition(_userStatus.underlying, deltaPositionUnderlying);
        _stableAssetStatus.updatePosition(_userStatus.stable, deltaPositionStable);

        return true;
    }

    function updateFeeAndPremiumGrowth(
        SqrtPerpAssetStatus storage _assetStatus,
        InterestRateModel.IRMParams memory _squartIRMParams,
        bool _isMarginZero,
        uint256 _lastUpdateTimestamp
    ) internal returns (uint256) {
        if (_lastUpdateTimestamp >= block.timestamp) {
            return 0;
        }

        updateFeeGrowth(_assetStatus);

        return updatePremiumGrowth(_assetStatus, _squartIRMParams, _isMarginZero, _lastUpdateTimestamp);
    }

    function updateFeeGrowth(SqrtPerpAssetStatus storage _assetStatus) internal {
        uint128 totalLiquidityAmount = getAvailableLiquidityAmount(
            address(this), _assetStatus.uniswapPool, _assetStatus.tickLower, _assetStatus.tickUpper
        );

        if (totalLiquidityAmount == 0) {
            return;
        }

        // collect trade fee
        IUniswapV3Pool(_assetStatus.uniswapPool).burn(_assetStatus.tickLower, _assetStatus.tickUpper, 0);

        (uint256 tradeFeeAmount0, uint256 tradeFeeAmount1) = IUniswapV3Pool(_assetStatus.uniswapPool).collect(
            address(this), _assetStatus.tickLower, _assetStatus.tickUpper, type(uint128).max, type(uint128).max
        );

        _assetStatus.fee0Growth += tradeFeeAmount0 * Constants.ONE / _assetStatus.totalAmount;
        _assetStatus.fee1Growth += tradeFeeAmount1 * Constants.ONE / _assetStatus.totalAmount;
    }

    function updatePremiumGrowth(
        SqrtPerpAssetStatus storage _assetStatus,
        InterestRateModel.IRMParams memory _squartIRMParams,
        bool _isMarginZero,
        uint256 _lastUpdateTimestamp
    ) internal returns (uint256) {
        uint256 utilization = getUtilizationRatio(_assetStatus);

        if (utilization == 0) {
            return 0;
        }

        uint256 interestRate = computePremium(
            _squartIRMParams,
            utilization,
            UniHelper.convertSqrtPrice(UniHelper.getSqrtPrice(_assetStatus.uniswapPool), _isMarginZero)
        ) * (block.timestamp - _lastUpdateTimestamp) / 365 days;

        uint256 borrowPremiumGrowth;
        uint256 supplyPremiumGrowth;

        borrowPremiumGrowth = interestRate;

        uint256 protocolFeePerLiquidity = (borrowPremiumGrowth * Constants.LPT_RESERVE_FACTOR) / Constants.ONE;

        supplyPremiumGrowth = ((borrowPremiumGrowth - protocolFeePerLiquidity) * utilization) / Constants.ONE;

        _assetStatus.borrowPremiumGrowth += borrowPremiumGrowth;
        _assetStatus.supplyPremiumGrowth += supplyPremiumGrowth;

        return (protocolFeePerLiquidity * _assetStatus.borrowedAmount) / Constants.ONE;
    }

    function computePremium(
        InterestRateModel.IRMParams memory _squartIRMParams,
        uint256 _utilization,
        uint256 _sqrtPrice
    ) internal pure returns (uint256 interestRate) {
        uint256 variance = InterestRateModel.calculateInterestRate(_squartIRMParams, _utilization);

        return (_sqrtPrice * variance) >> FixedPoint96.RESOLUTION;
    }

    /**
     * @notice Computes reuired amounts to increase or decrease sqrt positions.
     * (L/sqrt{x}, L * sqrt{x})
     */
    function computeRequiredAmounts(
        DataType.AssetStatus memory _underlyingAssetStatus,
        UserStatus memory _userStatus,
        int256 _tradeSqrtAmount
    ) internal returns (int256 requiredAmountUnderlying, int256 requiredAmountStable) {
        if (_tradeSqrtAmount == 0) {
            return (0, 0);
        }

        require(Reallocation.isInRange(_underlyingAssetStatus.sqrtAssetStatus), "P2");

        int256 requiredAmount0;
        int256 requiredAmount1;

        if (_tradeSqrtAmount > 0) {
            (requiredAmount0, requiredAmount1) =
                increase(_underlyingAssetStatus.sqrtAssetStatus, uint256(_tradeSqrtAmount));
        } else if (_tradeSqrtAmount < 0) {
            (requiredAmount0, requiredAmount1) =
                decrease(_underlyingAssetStatus.sqrtAssetStatus, uint256(-_tradeSqrtAmount));
        }

        if (_underlyingAssetStatus.isMarginZero) {
            requiredAmountStable = requiredAmount0;
            requiredAmountUnderlying = requiredAmount1;
        } else {
            requiredAmountStable = requiredAmount1;
            requiredAmountUnderlying = requiredAmount0;
        }

        (int256 offsetUnderlying, int256 offsetStable) = calculateSqrtPerpOffset(
            _userStatus,
            _underlyingAssetStatus.sqrtAssetStatus.tickLower,
            _underlyingAssetStatus.sqrtAssetStatus.tickUpper,
            _tradeSqrtAmount,
            _underlyingAssetStatus.isMarginZero
        );

        requiredAmountUnderlying -= offsetUnderlying;
        requiredAmountStable -= offsetStable;
    }

    function updatePosition(
        DataType.AssetStatus storage _underlyingAssetStatus,
        ScaledAsset.TokenStatus storage _stableAssetStatus,
        UserStatus storage _userStatus,
        UpdatePerpParams memory _updatePerpParams,
        UpdateSqrtPerpParams memory _updateSqrtPerpParams
    ) internal returns (Payoff memory payoff) {
        (payoff.perpEntryUpdate, payoff.perpPayoff) = calculateEntry(
            _userStatus.perp.amount,
            _userStatus.perp.entryValue,
            _updatePerpParams.tradeAmount,
            _updatePerpParams.stableAmount
        );

        (payoff.sqrtRebalanceEntryUpdateUnderlying, payoff.sqrtRebalanceEntryUpdateStable) = calculateSqrtPerpOffset(
            _userStatus,
            _underlyingAssetStatus.sqrtAssetStatus.tickLower,
            _underlyingAssetStatus.sqrtAssetStatus.tickUpper,
            _updateSqrtPerpParams.tradeSqrtAmount,
            _underlyingAssetStatus.isMarginZero
        );

        (payoff.sqrtEntryUpdate, payoff.sqrtPayoff) = calculateEntry(
            _userStatus.sqrtPerp.amount,
            _userStatus.sqrtPerp.entryValue,
            _updateSqrtPerpParams.tradeSqrtAmount,
            _updateSqrtPerpParams.stableAmount
        );

        _userStatus.perp.amount += _updatePerpParams.tradeAmount;

        // Update entry value
        _userStatus.perp.entryValue += payoff.perpEntryUpdate;
        _userStatus.sqrtPerp.entryValue += payoff.sqrtEntryUpdate;
        _userStatus.sqrtPerp.stableRebalanceEntryValue += payoff.sqrtRebalanceEntryUpdateStable;
        _userStatus.sqrtPerp.underlyingRebalanceEntryValue += payoff.sqrtRebalanceEntryUpdateUnderlying;

        // Update fee entry
        _userStatus.sqrtPerp.entryTradeFee0 = _underlyingAssetStatus.sqrtAssetStatus.fee0Growth;
        _userStatus.sqrtPerp.entryTradeFee1 = _underlyingAssetStatus.sqrtAssetStatus.fee1Growth;

        // Update sqrt position
        updateSqrtPosition(_underlyingAssetStatus.sqrtAssetStatus, _userStatus, _updateSqrtPerpParams.tradeSqrtAmount);

        _underlyingAssetStatus.tokenStatus.updatePosition(
            _userStatus.underlying, _updatePerpParams.tradeAmount + payoff.sqrtRebalanceEntryUpdateUnderlying
        );

        _stableAssetStatus.updatePosition(
            _userStatus.stable, payoff.perpEntryUpdate + payoff.sqrtEntryUpdate + payoff.sqrtRebalanceEntryUpdateStable
        );
    }

    function updateSqrtPosition(
        SqrtPerpAssetStatus storage _assetStatus,
        UserStatus storage _userStatus,
        int256 _amount
    ) internal {
        int256 openAmount;
        int256 closeAmount;

        if (_userStatus.sqrtPerp.amount * _amount >= 0) {
            openAmount = _amount;
        } else {
            if (_userStatus.sqrtPerp.amount.abs() >= _amount.abs()) {
                closeAmount = _amount;
            } else {
                openAmount = _userStatus.sqrtPerp.amount + _amount;
                closeAmount = -_userStatus.sqrtPerp.amount;
            }
        }

        if (closeAmount > 0) {
            _assetStatus.borrowedAmount -= uint256(closeAmount);
        } else if (closeAmount < 0) {
            require(getAvailableSqrtAmount(_assetStatus) >= uint256(-closeAmount), "S0");
            _assetStatus.totalAmount -= uint256(-closeAmount);
        }

        if (openAmount > 0) {
            _assetStatus.totalAmount += uint256(openAmount);

            // TODO: collect fee before update position
            _userStatus.sqrtPerp.entryPremium = _assetStatus.supplyPremiumGrowth;
        } else if (openAmount < 0) {
            require(getAvailableSqrtAmount(_assetStatus) >= uint256(-openAmount), "S0");

            _assetStatus.borrowedAmount += uint256(-openAmount);

            // TODO: pay fee before update position
            _userStatus.sqrtPerp.entryPremium = _assetStatus.borrowPremiumGrowth;
        }

        _userStatus.sqrtPerp.amount += _amount;
    }

    function getAvailableSqrtAmount(SqrtPerpAssetStatus memory _assetStatus) internal pure returns (uint256) {
        return _assetStatus.totalAmount - _assetStatus.borrowedAmount;
    }

    function getUtilizationRatio(SqrtPerpAssetStatus memory _assetStatus) internal pure returns (uint256) {
        if (_assetStatus.totalAmount == 0) {
            return 0;
        }

        uint256 utilization = _assetStatus.borrowedAmount * Constants.ONE / _assetStatus.totalAmount;

        if (utilization > 1e18) {
            return 1e18;
        }

        return utilization;
    }

    function updateRebalanceEntry(
        SqrtPerpAssetStatus storage _assetStatus,
        UserStatus storage _userStatus,
        bool _isMarginZero
    ) internal returns (int256 rebalancePositionUpdateUnderlying, int256 rebalancePositionUpdateStable) {
        // Rebalance position should be over repayed or deposited.
        // rebalancePositionUpdate values must be rounded down to a smaller value.

        if (_userStatus.sqrtPerp.amount == 0) {
            _userStatus.rebalanceLastTickLower = _assetStatus.tickLower;
            _userStatus.rebalanceLastTickUpper = _assetStatus.tickUpper;

            return (0, 0);
        }

        int256 deltaPosition0 = LPMath.calculateAmount0ForLiquidityWithTicks(
            _assetStatus.tickUpper,
            _userStatus.rebalanceLastTickUpper,
            _userStatus.sqrtPerp.amount.abs(),
            _userStatus.sqrtPerp.amount < 0
        );

        int256 deltaPosition1 = LPMath.calculateAmount1ForLiquidityWithTicks(
            _assetStatus.tickLower,
            _userStatus.rebalanceLastTickLower,
            _userStatus.sqrtPerp.amount.abs(),
            _userStatus.sqrtPerp.amount < 0
        );

        _userStatus.rebalanceLastTickLower = _assetStatus.tickLower;
        _userStatus.rebalanceLastTickUpper = _assetStatus.tickUpper;

        if (_userStatus.sqrtPerp.amount < 0) {
            deltaPosition0 = -deltaPosition0;
            deltaPosition1 = -deltaPosition1;
        }

        if (_isMarginZero) {
            rebalancePositionUpdateUnderlying = deltaPosition1;
            rebalancePositionUpdateStable = deltaPosition0;
        } else {
            rebalancePositionUpdateUnderlying = deltaPosition0;
            rebalancePositionUpdateStable = deltaPosition1;
        }
    }

    function calculateEntry(int256 _positionAmount, int256 _entryValue, int256 _tradeAmount, int256 _valueUpdate)
        internal
        pure
        returns (int256 deltaEntry, int256 payoff)
    {
        if (_tradeAmount == 0) {
            return (0, 0);
        }

        if (_positionAmount * _tradeAmount >= 0) {
            // open position
            deltaEntry = _valueUpdate;
        } else {
            if (_positionAmount.abs() >= _tradeAmount.abs()) {
                // close position

                int256 closeStableAmount = _entryValue * _tradeAmount / _positionAmount;

                deltaEntry = closeStableAmount;
                payoff = _valueUpdate - closeStableAmount;
            } else {
                // close full and open position

                int256 closeStableAmount = -_entryValue;
                int256 openStableAmount = _valueUpdate * (_positionAmount + _tradeAmount) / _tradeAmount;

                deltaEntry = closeStableAmount + openStableAmount;
                payoff = _valueUpdate - closeStableAmount - openStableAmount;
            }
        }
    }

    // private functions

    function increase(SqrtPerpAssetStatus memory _assetStatus, uint256 _liquidityAmount)
        internal
        returns (int256 requiredAmount0, int256 requiredAmount1)
    {
        (uint256 amount0, uint256 amount1) = IUniswapV3Pool(_assetStatus.uniswapPool).mint(
            address(this), _assetStatus.tickLower, _assetStatus.tickUpper, _liquidityAmount.safeCastTo128(), ""
        );

        requiredAmount0 = -SafeCast.toInt256(amount0);
        requiredAmount1 = -SafeCast.toInt256(amount1);
    }

    function decrease(SqrtPerpAssetStatus memory _assetStatus, uint256 _liquidityAmount)
        internal
        returns (int256 receivedAmount0, int256 receivedAmount1)
    {
        require(_assetStatus.totalAmount - _assetStatus.borrowedAmount >= _liquidityAmount, "P1");

        (uint256 amount0, uint256 amount1) = IUniswapV3Pool(_assetStatus.uniswapPool).burn(
            _assetStatus.tickLower, _assetStatus.tickUpper, _liquidityAmount.safeCastTo128()
        );

        // collect burned token amounts
        IUniswapV3Pool(_assetStatus.uniswapPool).collect(
            address(this),
            _assetStatus.tickLower,
            _assetStatus.tickUpper,
            amount0.safeCastTo128(),
            amount1.safeCastTo128()
        );

        receivedAmount0 = SafeCast.toInt256(amount0);
        receivedAmount1 = SafeCast.toInt256(amount1);
    }

    function getAmounts(
        SqrtPerpAssetStatus memory _assetStatus,
        UserStatus memory _userStatus,
        bool _isMarginZero,
        uint160 _sqrtPrice
    )
        internal
        pure
        returns (
            uint256 assetAmountUnderlying,
            uint256 assetAmountStable,
            uint256 debtAmountUnderlying,
            uint256 debtAmountStable
        )
    {
        {
            (uint256 amount0InUniswap, uint256 amount1InUniswap) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                TickMath.getSqrtRatioAtTick(_assetStatus.tickLower),
                TickMath.getSqrtRatioAtTick(_assetStatus.tickUpper),
                _userStatus.sqrtPerp.amount.abs().safeCastTo128()
            );

            if (_userStatus.sqrtPerp.amount > 0) {
                if (_isMarginZero) {
                    assetAmountStable = amount0InUniswap;
                    assetAmountUnderlying = amount1InUniswap;
                } else {
                    assetAmountUnderlying = amount0InUniswap;
                    assetAmountStable = amount1InUniswap;
                }
            } else {
                if (_isMarginZero) {
                    debtAmountStable = amount0InUniswap;
                    debtAmountUnderlying = amount1InUniswap;
                } else {
                    debtAmountUnderlying = amount0InUniswap;
                    debtAmountStable = amount1InUniswap;
                }
            }
        }

        if (_userStatus.stable.positionAmount > 0) {
            assetAmountStable += uint256(_userStatus.stable.positionAmount);
        }

        if (_userStatus.stable.positionAmount < 0) {
            debtAmountStable += uint256(-_userStatus.stable.positionAmount);
        }

        if (_userStatus.underlying.positionAmount > 0) {
            assetAmountUnderlying += uint256(_userStatus.underlying.positionAmount);
        }

        if (_userStatus.underlying.positionAmount < 0) {
            debtAmountUnderlying += uint256(-_userStatus.underlying.positionAmount);
        }
    }

    /**
     * @notice Calculates sqrt perp offset
     * open: (L/sqrt{b}, L * sqrt{a})
     * close: (-L * e0, -L * e1)
     */
    function calculateSqrtPerpOffset(
        UserStatus memory _userStatus,
        int24 _tickLower,
        int24 _tickUpper,
        int256 _tradeSqrtAmount,
        bool _isMarginZero
    ) internal pure returns (int256 offsetUnderlying, int256 offsetStable) {
        int256 openAmount;
        int256 closeAmount;

        if (_userStatus.sqrtPerp.amount * _tradeSqrtAmount >= 0) {
            openAmount = _tradeSqrtAmount;
        } else {
            if (_userStatus.sqrtPerp.amount.abs() >= _tradeSqrtAmount.abs()) {
                closeAmount = _tradeSqrtAmount;
            } else {
                openAmount = _userStatus.sqrtPerp.amount + _tradeSqrtAmount;
                closeAmount = -_userStatus.sqrtPerp.amount;
            }
        }

        if (openAmount != 0) {
            // L / sqrt(b)
            offsetUnderlying = LPMath.calculateAmount0OffsetWithTick(_tickUpper, openAmount.abs(), openAmount < 0);

            // L * sqrt(a)
            offsetStable = LPMath.calculateAmount1OffsetWithTick(_tickLower, openAmount.abs(), openAmount < 0);

            if (openAmount < 0) {
                offsetUnderlying = -offsetUnderlying;
                offsetStable = -offsetStable;
            }

            if (_isMarginZero) {
                // Swap if the pool is Stable-Underlying pair
                (offsetUnderlying, offsetStable) = (offsetStable, offsetUnderlying);
            }
        }

        if (closeAmount != 0) {
            offsetStable += closeAmount * _userStatus.sqrtPerp.stableRebalanceEntryValue / _userStatus.sqrtPerp.amount;
            offsetUnderlying +=
                closeAmount * _userStatus.sqrtPerp.underlyingRebalanceEntryValue / _userStatus.sqrtPerp.amount;
        }
    }

    function updateRebalancePosition(
        DataType.AssetStatus storage _assetStatusUnderlying,
        ScaledAsset.TokenStatus storage _assetStatusStable,
        int256 _updateAmount0,
        int256 _updateAmount1
    ) internal {
        SqrtPerpAssetStatus storage sqrtAsset = _assetStatusUnderlying.sqrtAssetStatus;

        if (_assetStatusUnderlying.isMarginZero) {
            _assetStatusStable.updatePosition(sqrtAsset.rebalancePositionStable, _updateAmount0);
            _assetStatusUnderlying.tokenStatus.updatePosition(sqrtAsset.rebalancePositionUnderlying, _updateAmount1);
        } else {
            _assetStatusUnderlying.tokenStatus.updatePosition(sqrtAsset.rebalancePositionUnderlying, _updateAmount0);
            _assetStatusStable.updatePosition(sqrtAsset.rebalancePositionStable, _updateAmount1);
        }
    }
}

