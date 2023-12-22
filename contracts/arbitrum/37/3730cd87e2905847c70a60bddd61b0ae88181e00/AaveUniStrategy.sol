// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./AaveActions.sol";
import "./UniswapActions.sol";

contract AaveUniStrategy is UniswapActions, AaveActions {
    using SafeTransferLib for ERC20;

    ERC20 internal immutable _usdc;
    ERC20 internal immutable _weth;
    bool internal immutable _wethIsToken0;
    uint256 private _targetHedgeFactor;
    uint256 private _allowUnderHedge;
    uint256 private _allowOverHedge;
    uint256 public totalUnitsDeposited;

    bool public paused = false;

    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    modifier slippage(int24 desired, int24 maxDiff) {
        int24 currentTick = getCurrentTick();
        require(diff(currentTick, desired) <= 10, "slippage");
        _;
    }

    constructor(
        address usdc,
        address weth,
        uint256 targetHedgeFactor,
        uint256 allowUnderHedge,
        uint256 allowOverHedge,
        address pool,
        uint24 rangeBuffer,
        int24 distanceLower,
        int24 distanceUpper,
        uint32 movingAverageDuration,
        address lendingPool,
        bool useAaveV2
    )
        UniswapActions(pool, rangeBuffer, distanceLower, distanceUpper, movingAverageDuration)
        AaveActions(lendingPool, useAaveV2, usdc, weth)
    {
        _usdc = ERC20(usdc);
        _weth = ERC20(weth);
        _targetHedgeFactor = targetHedgeFactor;
        _allowUnderHedge = allowUnderHedge;
        _allowOverHedge = allowOverHedge;
        _wethIsToken0 = weth < usdc;
    }

    function getStrategyParameters()
        external
        view
        returns (uint256 targetHedgeFactor, uint256 allowUnderHedge, uint256 allowOverHedge)
    {
        targetHedgeFactor = _targetHedgeFactor;
        allowUnderHedge = _allowUnderHedge;
        allowOverHedge = _allowOverHedge;
    }

    function getVirtualPrice() public view returns (uint256 virtualPrice) {
        if (totalUnitsDeposited > 0) {
            virtualPrice = 1e18 * getTotalValue() / totalUnitsDeposited;
        }
    }

    function getTotalValue() public view returns (uint256 usdValue) {
        (uint256 usdcBalance, uint256 wethBalance, uint256 wethDebt) = getAssets(false);
        uint256 wethValue = getSimpleQuote(_wethIsToken0, wethBalance);
        uint256 debtValue = getSimpleQuote(_wethIsToken0, wethDebt);
        usdValue = usdcBalance + wethValue - debtValue;
    }

    function getAssets(bool useMovingAverage)
        public
        view
        returns (uint256 usdcBalance, uint256 wethBalance, uint256 wethDebt)
    {
        (uint256 amount0, uint256 amount1) = useMovingAverage ? assetsInV3Average() : assetsInV3Exact();
        if (_wethIsToken0) {
            wethBalance = amount0;
            usdcBalance = amount1;
        } else {
            wethBalance = amount1;
            usdcBalance = amount0;
        }
        wethBalance += _weth.balanceOf(address(this));
        usdcBalance += _usdc.balanceOf(address(this));
        usdcBalance += getDepositedAmount(_usdc);
        wethDebt = getBorrowedAmount(_weth);
    }

    function hedgeStatus(bool useMovingAverage)
        public
        view
        returns (bool needsRebalancing, uint256 factor, uint256 ethAmount)
    {
        (, uint256 wethBalance, uint256 wethDebt) = getAssets(useMovingAverage);
        return _hedgeStatus(wethBalance, wethDebt);
    }

    function healthFactorStatus() public view returns (bool needsRebalancing, uint256 factor, uint256 ethAmount) {
        (uint256 am0, uint256 am1) = getReserveRatio();
        if (_wethIsToken0) {
            return _healthFactorStatus(am0 * 1e18 / am1);
        } else {
            return _healthFactorStatus(am1 * 1e18 / am0);
        }
    }

    function setHedgeParameters(uint256 targetHedgeFactor, uint256 allowOverHedge, uint256 allowUnderHedge)
        external
        onlyAuthorised
    {
        _targetHedgeFactor = targetHedgeFactor;
        _allowOverHedge = allowOverHedge;
        _allowUnderHedge = allowUnderHedge;
    }

    function deploy(uint256 usdcAmount, uint128 minLiquidityAddeed)
        external
        notPaused
        onlyAuthorised
        returns (uint256 amount0, uint256 amount1, uint128 liquidityAdded)
    {
        _increaseUnitsDeposited(usdcAmount);
        _usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        uint256 ratio = getValueRatio(_wethIsToken0);
        uint256 collateralisationRatio = targetCollateralisationRatio();
        uint256 collateralAmount = 1e18 * usdcAmount / (1e18 + 1e18 * ratio / collateralisationRatio);
        _deposit(_usdc, collateralAmount);
        usdcAmount -= collateralAmount;
        uint256 wethAmount = matchAmountForAmount(!_wethIsToken0, usdcAmount);
        _borrow(_weth, wethAmount);
        if (_wethIsToken0) {
            (amount0, amount1, liquidityAdded) = _addLiquidity(wethAmount, usdcAmount, minLiquidityAddeed);
        } else {
            (amount0, amount1, liquidityAdded) = _addLiquidity(usdcAmount, wethAmount, minLiquidityAddeed);
        }
    }

    // Not appropriate to take out 100% of the assets.
    function exit(uint256 usdcAmount, address to) external onlyOwner {
        if (_wethIsToken0) {
            uint128 liquidity = _getLiquidityForAmount1(usdcAmount / 2);
            _removeLiquidity(liquidity);
        } else {
            uint128 liquidity = _getLiquidityForAmount0(usdcAmount / 2);
            _removeLiquidity(liquidity);
        }
        _decreaseUnitsDeposited(usdcAmount);
        _repayMax(_weth);
        _depositMax(_usdc);
        _withdraw(_usdc, usdcAmount);
        _usdc.safeTransfer(to, usdcAmount);
    }

    function maintainHedge(int24 priceTick, int24 maxDifference)
        external
        onlyAuthorised
        notPaused
        slippage(priceTick, maxDifference)
        returns (uint256 liquidityRemoved, uint256 collateralAdded, uint256 debtRepaid)
    {
        (bool fixHedge, uint256 hedgeFactor, uint256 amount) = hedgeStatus(true); // amount is in ETH
        if (!fixHedge) return (0, 0, 0);

        if (hedgeFactor > _targetHedgeFactor) {
            // remove lp, sell weth, deposit usdc
            uint128 liquidity = _wethIsToken0 ? _getLiquidityForAmount0(amount) : _getLiquidityForAmount1(amount);
            (liquidity,,) = _removeLiquidity(liquidity);
            _swap(_wethIsToken0, amount, 0);
            return (liquidity, _depositMax(_usdc), 0);
        } else if (hedgeFactor < _targetHedgeFactor) {
            // remove lp, buy weth, repay
            uint256 usdcToSell = getSimpleQuote(_wethIsToken0, amount);
            uint128 liquidity =
                _wethIsToken0 ? _getLiquidityForAmount1(usdcToSell) : _getLiquidityForAmount0(usdcToSell);
            (liquidity,,) = _removeLiquidity(liquidity);
            _swap(!_wethIsToken0, usdcToSell, 0);
            return (liquidity, 0, _repayMax(_weth));
        }
    }

    function maintainHealthFactor(int24 priceTick, int24 maxDifference)
        external
        onlyAuthorised
        notPaused
        slippage(priceTick, maxDifference)
        returns (int256 liquidityChange, int256 collateralChange, int256 debtChange)
    {
        (bool fixHealthFactor, uint256 healthFactor, uint256 ethAmount) = healthFactorStatus();
        if (!fixHealthFactor) return (0, 0, 0);
        ethAmount = 1e18 * ethAmount / (1e18 + 8500 * getValueRatio(_wethIsToken0) / 1e4);

        if (healthFactor > _targetHealthFactor) {
            _borrow(_weth, ethAmount);
            uint256 usdcAmount = matchAmountForAmount(_wethIsToken0, ethAmount);
            _withdraw(_usdc, usdcAmount);
            (,, uint128 liquidity) = _addMaxLiquidity(0);
            return (int256(uint256(liquidity)), -int256(usdcAmount), -int256(ethAmount));
        } else {
            uint128 liquidity = _wethIsToken0 ? _getLiquidityForAmount0(ethAmount) : _getLiquidityForAmount1(ethAmount);
            _removeLiquidity(liquidity);
            uint256 ethRepaid = _repayMax(_weth);
            uint256 usdcDeposited = _depositMax(_usdc);
            return (-int256(uint256(liquidity)), int256(usdcDeposited), int256(ethRepaid));
        }
    }

    function resetRange(uint128 minLiquidityAdded)
        external
        onlyAuthorised
        notPaused
        returns (uint256 amount0, uint256 amount1, uint128 liquidity)
    {
        _collectFees();
        (amount0, amount1, liquidity) = _resetRange();
        if (liquidity > 0) {
            (amount0, amount1, liquidity) = _addLiquidity(amount0, amount1, minLiquidityAdded);
            _repayMax(_weth);
            _depositMax(_usdc);
        }
    }

    function addLiquidity(uint256 desired0, uint256 desired1, uint128 minimum)
        external
        onlyAuthorised
        returns (uint256 amount0, uint256 amount1, uint128 minted)
    {
        return _addLiquidity(desired0, desired1, minimum);
    }

    function removeLiquidity(uint128 amount)
        external
        onlyAuthorised
        returns (uint256 removed, uint256 amount0, uint256 amount1)
    {
        return _removeLiquidity(amount);
    }

    function addMaxLiquidity(uint128 min)
        external
        onlyAuthorised
        returns (uint256 amount0, uint256 amount1, uint128 liquidity)
    {
        return _addMaxLiquidity(min);
    }

    function collectFees() external onlyAuthorised returns (uint256 amount0, uint256 amount1) {
        return _collectFees();
    }

    function depositMaxUSDC() external onlyAuthorised {
        _depositMax(_usdc);
    }

    function depositUSDC(uint256 amount) external onlyAuthorised {
        _deposit(_usdc, amount);
    }

    function withdrawUSDC(uint256 amount) external onlyAuthorised {
        _withdraw(_usdc, amount);
    }

    function withdrawMaxUSDC() external onlyAuthorised {
        _withdrawMax(_usdc);
    }

    function borrowWETH(uint256 amount) external onlyAuthorised {
        _borrow(_weth, amount);
    }

    function repayWETH(uint256 amount) external onlyAuthorised {
        _repay(_weth, amount);
    }

    function repayMaxWETH() external onlyAuthorised {
        _repayMax(_weth);
    }

    function swap(bool zeroForOne, uint256 amountIn, uint256 minimumAmountOut)
        external
        onlyAuthorised
        returns (uint256 amountOut)
    {
        return _swap(zeroForOne, amountIn, minimumAmountOut);
    }

    function _hedgeStatus(uint256 available, uint256 debt)
        internal
        view
        returns (bool needsRebalancing, uint256 factor, uint256 ethAmount)
    {
        if (debt == 0) debt++;
        if (available == 0) available++;
        factor = 1e18 * available / debt;
        needsRebalancing =
            factor > _targetHedgeFactor + _allowOverHedge || factor < _targetHedgeFactor - _allowUnderHedge;
        uint256 adjustedDebt = debt * _targetHedgeFactor / 1e18;
        ethAmount = available > adjustedDebt ? available - adjustedDebt : adjustedDebt - available;
    }

    function _increaseUnitsDeposited(uint256 usdcDeposited) internal {
        uint256 virtualPrice = getVirtualPrice();
        if (virtualPrice == 0) {
            totalUnitsDeposited = usdcDeposited;
        } else {
            totalUnitsDeposited += usdcDeposited * 1e18 / virtualPrice;
        }
    }

    function _decreaseUnitsDeposited(uint256 usdcWithdrawn) internal {
        uint256 virtualPrice = getVirtualPrice();
        if (virtualPrice == 0) {
            totalUnitsDeposited -= usdcWithdrawn;
        } else {
            totalUnitsDeposited -= usdcWithdrawn * 1e18 / virtualPrice;
        }
    }
}

