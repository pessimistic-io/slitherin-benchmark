// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20Upgradeable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IVault.sol";
import "./IVaultUtils.sol";

import "./Governable.sol";

contract VaultUtils is IVaultUtils, Governable {
    using SafeMath for uint256;

    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    IVault public vault;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;

    uint256 public constant MAX_WITHDRAWAL_COOLDOWN_DURATION = 30 days;
    uint256 public constant MIN_LEVERAGE_CAP = 10 * BASIS_POINTS_DIVISOR;

    uint256 public withdrawalCooldownDuration = 0;
    uint256 public minLeverage = 25000; // 2.5x

    constructor(IVault _vault) public {
        vault = _vault;
    }

    function setWithdrawalCooldownDuration(uint256 _withdrawalCooldownDuration)
        external
        onlyGov
    {
        require(
            _withdrawalCooldownDuration <= MAX_WITHDRAWAL_COOLDOWN_DURATION,
            "VaultUtils: Max withdrawal cooldown duration"
        );
        withdrawalCooldownDuration = _withdrawalCooldownDuration;
    }

    function setMinLeverage(uint256 _minLeverage) external onlyGov {
        require(
            _minLeverage <= MIN_LEVERAGE_CAP,
            "VaultUtils: Min leverage cap exceeded"
        );
        minLeverage = _minLeverage;
    }

    function updateCumulativeFundingRate(
        address, /* _collateralToken */
        address /* _indexToken */
    ) public override returns (bool) {
        return true;
    }

    function validateIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external view override {
        Position memory position = getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );

        uint256 prevBalance = vault.tokenBalances(_collateralToken);
        uint256 nextBalance = IERC20(_collateralToken).balanceOf(
            address(vault)
        );
        uint256 collateralDelta = nextBalance.sub(prevBalance);
        uint256 collateralDeltaUsd = vault.tokenToUsdMin(
            _collateralToken,
            collateralDelta
        );

        uint256 nextSize = position.size.add(_sizeDelta);
        uint256 nextCollateral = position.collateral.add(collateralDeltaUsd);

        if (nextCollateral > 0) {
            uint256 nextLeverage = nextSize.mul(BASIS_POINTS_DIVISOR + 1).div(
                nextCollateral
            );
            require(
                nextLeverage >= minLeverage,
                "VaultUtils: leverage is too low"
            );
        }
    }

    function validateDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address /* _receiver */
    ) external view override {
        Position memory position = getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );

        if (position.size > 0 && _sizeDelta < position.size) {
            bool isCooldown = position.lastIncreasedTime +
                withdrawalCooldownDuration >
                block.timestamp;

            uint256 prevLeverage = position.size.mul(BASIS_POINTS_DIVISOR).div(
                position.collateral
            );
            uint256 nextSize = position.size.sub(_sizeDelta);
            uint256 nextCollateral = position.collateral.sub(_collateralDelta);
            // use BASIS_POINTS_DIVISOR - 1 to allow for a 0.01% decrease in leverage even if within the cooldown duration
            uint256 nextLeverage = nextSize.mul(BASIS_POINTS_DIVISOR - 1).div(
                nextCollateral
            );

            require(
                nextLeverage >= minLeverage,
                "VaultUtils: leverage is too low"
            );

            bool isWithdrawal = nextLeverage > prevLeverage;

            if (isCooldown && isWithdrawal) {
                revert("VaultUtils: cooldown duration not yet passed");
            }
        }
    }

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal view returns (Position memory) {
        IVault _vault = vault;
        Position memory position;
        {
            (
                uint256 size,
                uint256 collateral,
                uint256 averagePrice,
                uint256 entryFundingRate, /* reserveAmount */ /* realisedPnl */ /* hasProfit */
                ,
                ,
                ,
                uint256 lastIncreasedTime
            ) = _vault.getPosition(
                    _account,
                    _collateralToken,
                    _indexToken,
                    _isLong
                );
            position.size = size;
            position.collateral = collateral;
            position.averagePrice = averagePrice;
            position.entryFundingRate = entryFundingRate;
            position.lastIncreasedTime = lastIncreasedTime;
        }
        return position;
    }

    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise
    ) public view override returns (uint256, uint256) {
        Position memory position = getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        IVault _vault = vault;

        (bool hasProfit, uint256 delta) = getDelta(
            _indexToken,
            position.size,
            position.averagePrice,
            _isLong,
            position.lastIncreasedTime
        );
        uint256 marginFees = getFundingFee(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size,
            position.entryFundingRate
        );
        marginFees = marginFees.add(
            getPositionFee(
                _account,
                _collateralToken,
                _indexToken,
                _isLong,
                position.size
            )
        );

        if (!hasProfit && position.collateral < delta) {
            if (_raise) {
                revert("Vault: losses exceed collateral");
            }
            return (1, marginFees);
        }

        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral.sub(delta);
        }

        if (remainingCollateral < marginFees) {
            if (_raise) {
                revert("Vault: fees exceed collateral");
            }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral);
        }

        if (remainingCollateral < marginFees.add(_vault.liquidationFeeUsd())) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            return (1, marginFees);
        }

        if (
            remainingCollateral.mul(_vault.maxLeverage()) <
            position.size.mul(BASIS_POINTS_DIVISOR)
        ) {
            if (_raise) {
                revert("Vault: maxLeverage exceeded");
            }
            return (2, marginFees);
        }

        return (0, marginFees);
    }

    function getEntryFundingRate(
        address _collateralToken,
        address, /* _indexToken */
        bool /* _isLong */
    ) public view override returns (uint256) {
        return vault.cumulativeFundingRates(_collateralToken);
    }

    function getPositionFee(
        address, /* _account */
        address, /* _collateralToken */
        address, /* _indexToken */
        bool, /* _isLong */
        uint256 _sizeDelta
    ) public view override returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }
        uint256 afterFeeUsd = _sizeDelta
            .mul(BASIS_POINTS_DIVISOR.sub(vault.marginFeeBasisPoints()))
            .div(BASIS_POINTS_DIVISOR);
        return _sizeDelta.sub(afterFeeUsd);
    }

    function getFundingFee(
        address, /* _account */
        address _collateralToken,
        address, /* _indexToken */
        bool, /* _isLong */
        uint256 _size,
        uint256 _entryFundingRate
    ) public view override returns (uint256) {
        if (_size == 0) {
            return 0;
        }

        uint256 fundingRate = vault
            .cumulativeFundingRates(_collateralToken)
            .sub(_entryFundingRate);
        if (fundingRate == 0) {
            return 0;
        }

        return _size.mul(fundingRate).div(FUNDING_RATE_PRECISION);
    }

    function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdgAmount)
        public
        view
        override
        returns (uint256)
    {
        return
            getFeeBasisPoints(
                _token,
                _usdgAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                true
            );
    }

    function getSellUsdgFeeBasisPoints(address _token, uint256 _usdgAmount)
        public
        view
        override
        returns (uint256)
    {
        return
            getFeeBasisPoints(
                _token,
                _usdgAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                false
            );
    }

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _usdgAmount
    ) public view override returns (uint256) {
        bool isStableSwap = vault.stableTokens(_tokenIn) &&
            vault.stableTokens(_tokenOut);
        uint256 baseBps = isStableSwap
            ? vault.stableSwapFeeBasisPoints()
            : vault.swapFeeBasisPoints();
        uint256 taxBps = isStableSwap
            ? vault.stableTaxBasisPoints()
            : vault.taxBasisPoints();
        uint256 feesBasisPoints0 = getFeeBasisPoints(
            _tokenIn,
            _usdgAmount,
            baseBps,
            taxBps,
            true
        );
        uint256 feesBasisPoints1 = getFeeBasisPoints(
            _tokenOut,
            _usdgAmount,
            baseBps,
            taxBps,
            false
        );
        // use the higher of the two fee basis points
        return
            feesBasisPoints0 > feesBasisPoints1
                ? feesBasisPoints0
                : feesBasisPoints1;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) public view override returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }

        uint256 initialAmount = vault.usdgAmounts(_token);
        uint256 nextAmount = initialAmount.add(_usdgDelta);
        if (!_increment) {
            nextAmount = _usdgDelta > initialAmount
                ? 0
                : initialAmount.sub(_usdgDelta);
        }

        uint256 targetAmount = getTargetUsdgAmount(_token);
        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount.sub(targetAmount)
            : targetAmount.sub(initialAmount);
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount.sub(targetAmount)
            : targetAmount.sub(nextAmount);

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = _taxBasisPoints.mul(initialDiff).div(
                targetAmount
            );
            return
                rebateBps > _feeBasisPoints
                    ? 0
                    : _feeBasisPoints.sub(rebateBps);
        }

        uint256 averageDiff = initialDiff.add(nextDiff).div(2);
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = _taxBasisPoints.mul(averageDiff).div(targetAmount);
        return _feeBasisPoints.add(taxBps);
    }

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) public view override returns (bool, uint256) {
        require(_averagePrice > 0, "38");
        uint256 price = _isLong
            ? vault.getMinPrice(_indexToken)
            : vault.getMaxPrice(_indexToken);
        uint256 priceDelta = _averagePrice > price
            ? _averagePrice.sub(price)
            : price.sub(_averagePrice);
        uint256 delta = _size.mul(priceDelta).div(_averagePrice);

        bool hasProfit;

        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        uint256 minBps = block.timestamp >
            _lastIncreasedTime.add(vault.minProfitTime())
            ? 0
            : vault.minProfitBasisPoints(_indexToken);
        if (hasProfit && delta.mul(BASIS_POINTS_DIVISOR) <= _size.mul(minBps)) {
            delta = 0;
        }

        return (hasProfit, delta);
    }

    function getTargetUsdgAmount(address _token)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = IERC20Upgradeable(vault.usdg()).totalSupply();
        if (supply == 0) {
            return 0;
        }
        uint256 weight = vault.tokenWeights(_token);
        return weight.mul(supply).div(vault.totalTokenWeights());
    }

    function getRedemptionCollateral(address _token)
        public
        view
        returns (uint256)
    {
        if (vault.stableTokens(_token)) {
            return vault.poolAmounts(_token);
        }
        uint256 collateral = vault.usdToTokenMin(
            _token,
            vault.guaranteedUsd(_token)
        );
        return
            collateral.add(vault.poolAmounts(_token)).sub(
                vault.reservedAmounts(_token)
            );
    }

    function getRedemptionCollateralUsd(address _token)
        public
        view
        returns (uint256)
    {
        return vault.tokenToUsdMin(_token, getRedemptionCollateral(_token));
    }

    function getUtilisation(address _token) public view returns (uint256) {
        uint256 poolAmount = vault.poolAmounts(_token);
        if (poolAmount == 0) {
            return 0;
        }

        return
            vault.reservedAmounts(_token).mul(FUNDING_RATE_PRECISION).div(
                poolAmount
            );
    }

    function getPositionLeverage(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (uint256) {
        (uint256 size, uint256 collateral, , , , , , ) = vault.getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        require(collateral > 0);
        return size.mul(BASIS_POINTS_DIVISOR).div(collateral);
    }

    function getGlobalShortDelta(address _token)
        public
        view
        returns (bool, uint256)
    {
        uint256 size = vault.globalShortSizes(_token);
        if (size == 0) {
            return (false, 0);
        }

        uint256 nextPrice = vault.getMaxPrice(_token);
        uint256 averagePrice = vault.globalShortAveragePrices(_token);
        uint256 priceDelta = averagePrice > nextPrice
            ? averagePrice.sub(nextPrice)
            : nextPrice.sub(averagePrice);
        uint256 delta = size.mul(priceDelta).div(averagePrice);
        bool hasProfit = averagePrice > nextPrice;

        return (hasProfit, delta);
    }

    function getPositionDelta(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (bool, uint256) {
        (
            uint256 size,
            ,
            uint256 averagePrice,
            ,
            ,
            ,
            ,
            uint256 lastIncreasedTime
        ) = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);
        return
            getDelta(
                _indexToken,
                size,
                averagePrice,
                _isLong,
                lastIncreasedTime
            );
    }
}

