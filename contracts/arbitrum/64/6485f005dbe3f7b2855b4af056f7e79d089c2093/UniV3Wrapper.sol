// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC4626, FixedPointMathLib} from "./ERC4626.sol";
import {SafeCast} from "./SafeCast.sol";
import {     LiquidityProviderBase,     IUniV3Pool,     ERC20,     TickMath,     LiquidityAmounts,     SafeTransferLib } from "./LiquidityProviderBase.sol";

contract UniV3Wrapper is ERC4626, LiquidityProviderBase {
    using SafeCast for uint256;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    constructor(address uniV3Pool, int24 _tickLower, int24 _tickUpper)
        ERC4626(ERC20(uniV3Pool), "Uniswap V3 LP wrapper", "LPT", 18)
        LiquidityProviderBase(uniV3Pool, _tickLower, _tickUpper)
    {}

    function pool() public view override returns (IUniV3Pool) {
        return IUniV3Pool(address(asset));
    }

    function getAssets() public view returns (uint256 amount0, uint256 amount1) {
        return getAssetsBasedOnPrice(getCurrentPrice());
    }

    function getAssetsBasedOnPrice(uint160 price) public view returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = getAmountsForLiquidity(totalLiquidity, price);
        (uint256 fees0, uint256 fees1) = getUnclaimedFees();
        amount0 += fees0 + balance0;
        amount1 += fees1 + balance1;
    }

    // Total assets represent the deposited liquidity in the pool.
    // This value does not include liquidity that will be compounded on deposits or withdrawals.
    function totalAssets() public view override returns (uint256) {
        return totalLiquidity;
    }

    function compound() public returns (uint256 amount0, uint256 amount1, uint128 liquidityAdded) {
        return _compound();
    }

    // Recommended way of entering the wrapper.
    // Call mintMaxLiquidityPreview() to get the swap amount.
    function zapIn(
        uint256 startingAmount0,
        uint256 startingAmount1,
        uint256 swapAmount,
        bool zeroForOne,
        uint256 swapMinimumOut
    ) external returns (uint256 swapAmountOut, uint256 liquidityMinted, uint256 sharesMinted) {
        _compound(); // Call compound here, so it doesn't get called in _add() as we need to preserve balances after the swap.
        swapAmountOut = _swap(zeroForOne, swapAmount, swapMinimumOut, msg.sender, address(this));
        if (zeroForOne) {
            startingAmount0 -= swapAmount;
            startingAmount1 += swapAmountOut;
        } else {
            startingAmount0 += swapAmountOut;
            startingAmount1 -= swapAmount;
        }
        (liquidityMinted,) = mintLiquidityPreview(startingAmount0, startingAmount1);
        (, sharesMinted) = _add(liquidityMinted, 0, msg.sender);
    }

    // Assets is the liquidity amount deposited.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        (, shares) = _add(assets, 0, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        (assets,) = _add(0, shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        (, shares) = _remove(assets, 0, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        (assets,) = _remove(0, shares, receiver, owner);
    }

    function _add(uint256 assets, uint256 shares, address receiver) internal returns (uint256, uint256) {
        _compound();
        if (assets == 0) {
            assets = previewMint(shares);
        } else {
            require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        }
        _addLiquidity(assets.toUint128(), msg.sender);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        return (assets, shares);
    }

    function _remove(uint256 assets, uint256 shares, address receiver, address owner)
        internal
        returns (uint256, uint256)
    {
        _compound();
        if (assets == 0) {
            require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");
        } else {
            shares = previewWithdraw(assets);
        }
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        _burn(owner, shares);
        _removeLiquidity(assets.toUint128(), receiver);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return (assets, shares);
    }
}

