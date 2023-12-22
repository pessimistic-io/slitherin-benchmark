// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IUniswapV3Pool.sol";
import "./FixedPointMathLib.sol";
import "./SafeCast.sol";
import "./UniHelper.sol";
import "./DataType.sol";
import "./Constants.sol";
import "./PerpFee.sol";
import "./Math.sol";

library PositionCalculator {
    using ScaledAsset for ScaledAsset.TokenStatus;
    using SafeCast for uint256;

    uint256 internal constant RISK_RATIO_ONE = 1e8;

    struct PositionParams {
        // x^0
        int256 amountStable;
        // x^0.5
        int256 amountSqrt;
        // x^1
        int256 amountUnderlying;
    }

    function isDanger(mapping(uint256 => DataType.AssetStatus) storage _assets, DataType.Vault memory _vault)
        internal
        view
    {
        (int256 minDeposit, int256 vaultValue, bool hasPosition) = calculateMinDeposit(_assets, _vault, true);

        if (!hasPosition) {
            revert("ND");
        }

        require(vaultValue < minDeposit || _vault.margin < 0, "ND");
    }

    function isSafe(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault memory _vault,
        bool _isLiquidationCall
    ) internal view returns (int256 minDeposit) {
        int256 vaultValue;
        bool hasPosition;

        // isSafe does not count unrealized fee
        (minDeposit, vaultValue, hasPosition) = calculateMinDeposit(_assets, _vault, false);

        // if it is liquidationCall and vault has no positions then skip margin check
        // because it can be insolvent vault
        if (_isLiquidationCall && !hasPosition) {
            return 0;
        }

        require(vaultValue >= minDeposit && _vault.margin >= 0, "NS");
    }

    function calculateMinDeposit(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault memory _vault,
        bool _enableUnrealizedFeeCalculation
    ) internal view returns (int256 minDeposit, int256 vaultValue, bool hasPosition) {
        int256 minValue;
        uint256 debtValue;

        (minValue, vaultValue, debtValue, hasPosition) =
            calculateMinValue(_assets, _vault, _enableUnrealizedFeeCalculation);

        int256 minMinValue = SafeCast.toInt256(calculateRequiredCollateralWithDebt() * debtValue / 1e6);

        minDeposit = vaultValue - minValue + minMinValue;

        if (hasPosition && minDeposit < Constants.MIN_MARGIN_AMOUNT) {
            minDeposit = Constants.MIN_MARGIN_AMOUNT;
        }
    }

    function calculateRequiredCollateralWithDebt() internal pure returns (uint256) {
        return Constants.BASE_MIN_COLLATERAL_WITH_DEBT;
    }

    /**
     * @notice Calculates min value of the vault.
     * @param _assets The mapping of assets
     * @param _vault The target vault for calculation
     * @param _enableUnrealizedFeeCalculation If true calculation count unrealized fee.
     */
    function calculateMinValue(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault memory _vault,
        bool _enableUnrealizedFeeCalculation
    ) internal view returns (int256 minValue, int256 vaultValue, uint256 debtValue, bool hasPosition) {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            DataType.UserStatus memory userStatus = _vault.openPositions[i];

            uint256 assetId = userStatus.assetId;

            if (_assets[assetId].sqrtAssetStatus.uniswapPool != address(0)) {
                uint160 sqrtPrice =
                    getSqrtPrice(_assets[assetId].sqrtAssetStatus.uniswapPool, _assets[assetId].isMarginZero);

                PositionParams memory positionParams;
                if (_enableUnrealizedFeeCalculation) {
                    positionParams = getPositionWithUnrealizedFee(
                        _assets[Constants.STABLE_ASSET_ID], _assets[assetId], userStatus.perpTrade
                    );
                } else {
                    positionParams = getPosition(userStatus.perpTrade);
                }

                minValue += calculateMinValue(sqrtPrice, positionParams, _assets[assetId].riskParams.riskRatio);

                vaultValue += calculateValue(sqrtPrice, positionParams);

                debtValue += calculateSquartDebtValue(sqrtPrice, userStatus.perpTrade);

                hasPosition = hasPosition || getHasPositionFlag(userStatus.perpTrade);
            }
        }

        minValue += int256(_vault.margin);
        vaultValue += int256(_vault.margin);
    }

    function getSqrtPrice(address _uniswapPool, bool _isMarginZero) internal view returns (uint160 sqrtPriceX96) {
        return UniHelper.convertSqrtPrice(UniHelper.getSqrtTWAP(_uniswapPool), _isMarginZero);
    }

    function getPositionWithUnrealizedFee(
        DataType.AssetStatus memory _stableAsset,
        DataType.AssetStatus memory _underlyingAsset,
        Perp.UserStatus memory _perpUserStatus
    ) internal pure returns (PositionParams memory positionParams) {
        (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) =
            PerpFee.computeUserFee(_underlyingAsset, _stableAsset.tokenStatus, _perpUserStatus);

        return PositionParams(
            _perpUserStatus.perp.entryValue + _perpUserStatus.sqrtPerp.entryValue + unrealizedFeeStable,
            _perpUserStatus.sqrtPerp.amount,
            _perpUserStatus.perp.amount + unrealizedFeeUnderlying
        );
    }

    function getPosition(Perp.UserStatus memory _perpUserStatus)
        internal
        pure
        returns (PositionParams memory positionParams)
    {
        return PositionParams(
            _perpUserStatus.perp.entryValue + _perpUserStatus.sqrtPerp.entryValue,
            _perpUserStatus.sqrtPerp.amount,
            _perpUserStatus.perp.amount
        );
    }

    function getHasPositionFlag(Perp.UserStatus memory _perpUserStatus) internal pure returns (bool) {
        return _perpUserStatus.stable.positionAmount < 0 || _perpUserStatus.sqrtPerp.amount < 0
            || _perpUserStatus.underlying.positionAmount < 0;
    }

    /**
     * @notice Calculates min position value in the range `p/r` to `rp`.
     * MinValue := Min(v(rp), v(p/r), v((b/a)^2))
     * where `a` is underlying asset amount, `b` is Sqrt perp amount
     * and `c` is Stable asset amount.
     * r is risk parameter.
     */
    function calculateMinValue(uint256 _sqrtPrice, PositionParams memory _positionParams, uint256 _riskRatio)
        internal
        pure
        returns (int256 minValue)
    {
        minValue = type(int256).max;

        uint256 upperPrice = _sqrtPrice * _riskRatio / RISK_RATIO_ONE;
        uint256 lowerPrice = _sqrtPrice * RISK_RATIO_ONE / _riskRatio;

        {
            int256 v = calculateValue(upperPrice, _positionParams);
            if (v < minValue) {
                minValue = v;
            }
        }

        {
            int256 v = calculateValue(lowerPrice, _positionParams);
            if (v < minValue) {
                minValue = v;
            }
        }

        if (_positionParams.amountSqrt < 0 && _positionParams.amountUnderlying > 0) {
            uint256 minSqrtPrice =
                (uint256(-_positionParams.amountSqrt) * Constants.Q96) / uint256(_positionParams.amountUnderlying);

            if (lowerPrice < minSqrtPrice && minSqrtPrice < upperPrice) {
                int256 v = calculateValue(minSqrtPrice, _positionParams);

                if (v < minValue) {
                    minValue = v;
                }
            }
        }
    }

    /**
     * @notice Calculates position value.
     * PositionValue = a * x+b * sqrt(x) + c.
     * where `a` is underlying asset amount, `b` is Sqrt perp amount
     * and `c` is Stable asset amount
     */
    function calculateValue(uint256 _sqrtPrice, PositionParams memory _positionParams) internal pure returns (int256) {
        uint256 price = (_sqrtPrice * _sqrtPrice) >> Constants.RESOLUTION;

        return ((_positionParams.amountUnderlying * price.toInt256()) / int256(Constants.Q96))
            + (2 * (_positionParams.amountSqrt * _sqrtPrice.toInt256()) / int256(Constants.Q96))
            + _positionParams.amountStable;
    }

    function calculateSquartDebtValue(uint256 _sqrtPrice, Perp.UserStatus memory _perpUserStatus)
        internal
        pure
        returns (uint256)
    {
        int256 squartPosition = _perpUserStatus.sqrtPerp.amount;

        if (squartPosition > 0) {
            return 0;
        }

        return (2 * (uint256(-squartPosition) * _sqrtPrice) >> Constants.RESOLUTION);
    }
}

