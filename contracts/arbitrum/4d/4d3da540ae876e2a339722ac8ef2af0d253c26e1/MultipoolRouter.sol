// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {Multipool, MpAsset as UintMpAsset, MpContext as UintMpContext} from "./Multipool.sol";
import "./IUniswapV2Pair.sol";
import "./IERC20.sol";
import {MpAsset, MpContext, MpCommonMath} from "./MpCommonMath.sol";
import {MpComplexMath} from "./MpComplexMath.sol";

uint constant DENOMINATOR = 1e18;

contract MultipoolRouter {
    using {
        MpComplexMath.mintRev,
        MpComplexMath.burnRev,
        MpComplexMath.mint,
        MpComplexMath.burn,
        MpComplexMath.burnTrace
    } for MpContext;

    constructor() {}

    function mintWithSharesOut(address poolAddress, address assetAddress, uint sharesOut, uint amountInMax, address to)
        public
        returns (uint amount, uint refund)
    {
        MpAsset memory asset = Multipool(poolAddress).getAsset(assetAddress);
        // Transfer all amount in in case the last part will return via multipool
        IERC20(assetAddress).transferFrom(msg.sender, poolAddress, amountInMax);
        // No need to check sleepage because contract will fail if there is no
        // enough funst been transfered
        (uint _amount, uint _refund) = Multipool(poolAddress).mint(assetAddress, sharesOut, to);
        amount = asset.toNative(_amount);
        refund = asset.toNative(_refund);
    }

    function burnWithSharesIn(address poolAddress, address assetAddress, uint sharesIn, uint amountOutMin, address to)
        public
        returns (uint amount, uint refund)
    {
        MpAsset memory asset = Multipool(poolAddress).getAsset(assetAddress);
        IERC20(poolAddress).transferFrom(msg.sender, poolAddress, sharesIn);
        (uint _amount, uint _refund) = Multipool(poolAddress).burn(assetAddress, sharesIn, to);
        amount = asset.toNative(_amount);
        refund = asset.toNative(_refund);

        require(amount >= amountOutMin, "MULTIPOOL_ROUTER: SE");
    }

    function mintWithAmountIn(address poolAddress, address assetAddress, uint amountIn, uint sharesOutMin, address to)
        public
        returns (uint shares, uint refund)
    {
        (MpContext memory context, MpAsset memory asset, uint totalSupply) =
            Multipool(poolAddress).getMintData(assetAddress);
        {
            uint oldUsdCap = context.usdCap;
            amountIn = asset.to18(amountIn);
            uint amountOut = context.mint(asset, amountIn);
            shares = (amountOut * asset.price * totalSupply) / DENOMINATOR / oldUsdCap;
            require(shares >= sharesOutMin, "MULTIPOOL_ROUTER: SE");
        }

        IERC20(assetAddress).transferFrom(msg.sender, poolAddress, amountIn);

        (, uint _refund) = Multipool(poolAddress).mint(assetAddress, shares, to);
        refund = asset.toNative(_refund);
    }

    function burnWithAmountOut(address poolAddress, address assetAddress, uint amountOut, uint sharesInMax, address to)
        public
        returns (uint shares, uint refund)
    {
        (MpContext memory context, MpAsset memory asset, uint totalSupply) =
            Multipool(poolAddress).getBurnData(assetAddress);
        uint oldUsdCap = context.usdCap;
        amountOut = asset.to18(amountOut);

        uint requiredAmountIn = context.burnRev(asset, amountOut);
        shares = requiredAmountIn * asset.price * totalSupply / DENOMINATOR / oldUsdCap;
        require(shares <= sharesInMax, "MULTIPOOL_ROUTER: SE");

        IERC20(poolAddress).transferFrom(msg.sender, poolAddress, shares);
        (, uint _refund) = Multipool(poolAddress).burn(assetAddress, shares, to);
        refund = asset.toNative(_refund);
    }

    function swapWithAmountIn(
        address poolAddress,
        address assetInAddress,
        address assetOutAddress,
        uint amountIn,
        uint amountOutMin,
        address to
    ) public returns (uint amountOut, uint refundIn, uint refundOut) {
        address[4] memory addresses = [poolAddress, assetInAddress, assetOutAddress, to];
        uint[3] memory amounts = [amountIn, amountOutMin, 0]; // last is share
        (MpContext memory context, MpAsset memory assetIn, MpAsset memory assetOut, uint totalSupply) =
            Multipool(addresses[0]).getTradeData(addresses[1], addresses[2]);
        {
            {
                uint _amountIn = assetIn.to18(amounts[0]);
                // old usd cap
                uint oldCap = context.usdCap;
                uint mintAmountOut = context.mint(assetIn, _amountIn);
                // we use this stuff as a share ***vitalic inrease stack pls
                amounts[2] = mintAmountOut * assetIn.price * totalSupply / DENOMINATOR / oldCap;
            }
        }

        IERC20(addresses[1]).transferFrom(msg.sender, addresses[0], amounts[0]);
        (, uint _amountOut, uint _refundIn, uint _refundOut) =
            Multipool(addresses[0]).swap(addresses[1], addresses[2], amounts[2], addresses[3]);

        _amountOut = assetOut.toNative(_amountOut);
        _refundIn = assetIn.toNative(_refundIn);
        _refundOut = assetOut.toNative(_refundOut);

        require(_amountOut >= amounts[1], "MULTIPOOL_ROUTER: SE");
        return (_amountOut, _refundIn, _refundOut);
    }

    function swapWithAmountOut(
        address poolAddress,
        address assetInAddress,
        address assetOutAddress,
        uint amountOut,
        uint amountInMax,
        address to
    ) public returns (uint amountIn, uint refundIn, uint refundOut) {
        address[4] memory addresses = [poolAddress, assetInAddress, assetOutAddress, to];
        uint[3] memory amounts = [amountOut, amountInMax, 0]; // last is share

        (MpContext memory context, MpAsset memory assetIn, MpAsset memory assetOut, uint totalSupply) =
            Multipool(addresses[0]).getTradeData(addresses[1], addresses[2]);
        {
            uint oldUsdCap = context.usdCap;
            uint _amountOut = assetOut.to18(amountOut);
            (uint burnAmountIn,,) = context.burnTrace(assetOut, assetIn.price, _amountOut);
            amounts[2] = (burnAmountIn * assetOut.price * totalSupply) / DENOMINATOR / oldUsdCap;
        }

        IERC20(addresses[1]).transferFrom(msg.sender, addresses[0], amounts[1]);
        (uint _amountIn,, uint _refundIn, uint _refundOut) =
            Multipool(addresses[0]).swap(addresses[1], addresses[2], amounts[2], addresses[3]);
        _amountIn = assetIn.toNative(_amountIn);
        _refundIn = assetIn.toNative(_refundIn);
        _refundOut = assetOut.toNative(_refundOut);
        return (_amountIn, _refundIn, _refundOut);
    }

    function estimateMintSharesOut(address poolAddress, address assetAddress, uint amountIn)
        public
        view
        returns (uint sharesOut, uint assetPrice, uint sharePrice, uint cashbackIn)
    {
        (MpContext memory context, MpAsset memory asset, uint totalSupply) =
            Multipool(poolAddress).getMintData(assetAddress);
        amountIn = asset.to18(amountIn);
        uint oldUsdCap = context.usdCap;

        uint amountOut = context.mint(asset, amountIn);

        require(oldUsdCap != 0, "MULTIPOOL_ROUTER: NS");
        sharesOut = (amountOut * asset.price * totalSupply) / DENOMINATOR / oldUsdCap;

        cashbackIn = asset.toNative(context.userCashbackBalance);

        assetPrice = asset.price;
        sharePrice = oldUsdCap * DENOMINATOR / totalSupply;
    }

    function estimateMintAmountIn(address poolAddress, address assetAddress, uint sharesOut)
        public
        view
        returns (uint amountIn, uint assetPrice, uint sharePrice, uint cashbackIn)
    {
        (MpContext memory context, MpAsset memory asset, uint totalSupply) =
            Multipool(poolAddress).getMintData(assetAddress);
        uint oldUsdCap = context.usdCap;

        require(totalSupply != 0, "MULTIPOOL_ROUTER: NS");
        uint _amountIn = (sharesOut * oldUsdCap) * DENOMINATOR / asset.price / totalSupply;

        _amountIn = context.mintRev(asset, _amountIn);
        amountIn = asset.toNative(_amountIn);
        cashbackIn = asset.toNative(context.userCashbackBalance);

        assetPrice = asset.price;
        sharePrice = oldUsdCap * DENOMINATOR / totalSupply;
    }

    function estimateBurnAmountOut(address poolAddress, address assetAddress, uint sharesIn)
        public
        view
        returns (uint amountOut, uint assetPrice, uint sharePrice, uint cashbackOut)
    {
        (MpContext memory context, MpAsset memory asset, uint totalSupply) =
            Multipool(poolAddress).getBurnData(assetAddress);
        uint oldUsdCap = context.usdCap;

        uint amountIn = (sharesIn * oldUsdCap * DENOMINATOR) / asset.price / totalSupply;

        uint _amountOut = context.burn(asset, amountIn);
        amountOut = asset.toNative(_amountOut);

        cashbackOut = asset.toNative(context.userCashbackBalance);
        assetPrice = asset.price;
        sharePrice = oldUsdCap * DENOMINATOR / totalSupply;
    }

    function estimateBurnSharesIn(address poolAddress, address assetAddress, uint amountOut)
        public
        view
        returns (uint sharesIn, uint assetPrice, uint sharePrice, uint cashbackOut)
    {
        (MpContext memory context, MpAsset memory asset, uint totalSupply) =
            Multipool(poolAddress).getBurnData(assetAddress);
        uint oldUsdCap = context.usdCap;

        amountOut = asset.to18(amountOut);
        uint amountIn = context.burnRev(asset, amountOut);

        sharesIn = (amountIn * asset.price * totalSupply) / DENOMINATOR / oldUsdCap;

        cashbackOut = asset.toNative(context.userCashbackBalance);
        assetPrice = asset.price;
        sharePrice = oldUsdCap * DENOMINATOR / totalSupply;
    }

    function estimateSwapAmountOut(address poolAddress, address assetInAddress, address assetOutAddress, uint amountIn)
        public
        view
        returns (uint shares, uint amountOut, uint assetInPrice, uint assetOutPrice, uint cashbackIn, uint cashbackOut)
    {
        (MpContext memory context, MpAsset memory assetIn, MpAsset memory assetOut, uint totalSupply) =
            Multipool(poolAddress).getTradeData(assetInAddress, assetOutAddress);
        uint oldUsdCap = context.usdCap;

        amountIn = assetIn.to18(amountIn);
        uint mintAmountOut = context.mint(assetIn, amountIn);
        cashbackIn = assetIn.toNative(context.userCashbackBalance);
        context.userCashbackBalance = 0;

        shares = (mintAmountOut * assetIn.price * totalSupply) / DENOMINATOR / oldUsdCap;
        uint _shares = shares;

        uint burnAmountIn = (_shares * context.usdCap) * DENOMINATOR / assetOut.price / (totalSupply + shares);

        amountOut = context.burn(assetOut, burnAmountIn);
        cashbackOut = assetOut.toNative(context.userCashbackBalance);

        amountOut = assetOut.toNative(amountOut);
        assetInPrice = assetIn.price;
        assetOutPrice = assetOut.price;
    }

    function estimateSwapAmountIn(address poolAddress, address assetInAddress, address assetOutAddress, uint amountOut)
        public
        view
        returns (uint shares, uint amountIn, uint assetInPrice, uint assetOutPrice, uint cashbackIn, uint cashbackOut)
    {
        (MpContext memory context, MpAsset memory assetIn, MpAsset memory assetOut, uint totalSupply) =
            Multipool(poolAddress).getTradeData(assetInAddress, assetOutAddress);
        assetInPrice = assetIn.price;
        assetOutPrice = assetOut.price;
        uint oldUsdCap = context.usdCap;

        uint burnAmountIn;
        {
            uint _amountOut = assetOut.to18(amountOut);
            (uint _burnAmountIn, uint burnCashback,) = context.burnTrace(assetOut, assetIn.price, _amountOut);
            cashbackOut = assetOut.toNative(burnCashback);
            burnAmountIn = _burnAmountIn;
        }
        shares = (burnAmountIn * assetOut.price * totalSupply) / DENOMINATOR / oldUsdCap;
        uint _shares = shares;

        uint mintAmountOut = (_shares * context.usdCap) * DENOMINATOR / assetIn.price / totalSupply;

        amountIn = context.mintRev(assetIn, mintAmountOut);
        cashbackIn = assetIn.toNative(context.userCashbackBalance);
        amountIn = assetIn.toNative(amountIn);
    }
}

