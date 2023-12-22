// SPDX-License-Identifier: MIT

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IAggregatorV3} from "./interfaces_IAggregatorV3.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {UniswapV2Library} from "./UniswapV2Library.sol";
import {IERC20} from "./SafeERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

/**
 * @title AssetsPricing
 * @author JonesDAO
 * @notice Helper contract to aggregate the process of fetching prices internally across Metavaults V2 product.
 */
library AssetsPricing {
    //////////////////////////////////////////////////////////
    //                  CONSTANTS
    //////////////////////////////////////////////////////////

    // @notice Chainlink ETH/USD oracle (8 decimals)
    IAggregatorV3 public constant ETH_ORACLE = IAggregatorV3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    // @notice Chainlink USDC/USD oracle (8 decimals)
    IAggregatorV3 public constant USDC_ORACLE = IAggregatorV3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);

    // @notice Chainlink stETH/ETH oracle (18 decimals)
    IAggregatorV3 public constant ST_ETH_ORACLE = IAggregatorV3(0x07C5b924399cc23c24a95c8743DE4006a32b7f2a);

    // @notice Chainlink wstETH/stETH ratio oracle (18 decimals)
    IAggregatorV3 public constant WST_ETH_ORACLE = IAggregatorV3(0xB1552C5e96B312d0Bf8b554186F846C40614a540);

    // @notice Chainlink wstETH/ETH ratio oracle (18 decimals)
    IAggregatorV3 public constant WST_ETH_RATIO_ORACLE = IAggregatorV3(0xb523AE262D20A936BC152e6023996e46FDC2A95D);

    // @notice Curve's 2CRV
    IStableSwap public constant CRV = IStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    // @notice Used to normalize results to 18 decimals
    uint256 private constant STANDARD_DECIMALS = 1e18;

    // @notice Used to normalize USDC functions
    uint256 private constant USDC_DECIMALS = 1e6;

    //////////////////////////////////////////////////////////
    //                  UniV2 VIEW FUNCTIONS
    //////////////////////////////////////////////////////////

    /**
     * @param _lp Pool that will happen the token swap
     * @param _amountIn Amount of tokens that will be swapped
     * @param _tokenIn Received token
     * @param _tokenOut Wanted token
     * @return min amount of tokens with slippage applied
     */
    function getAmountOut(address _lp, uint256 _amountIn, address _tokenIn, address _tokenOut)
        external
        view
        returns (uint256)
    {
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(_lp, _tokenIn, _tokenOut);

        return UniswapV2Library.getAmountOut(_amountIn, reserveA, reserveB);
    }

    /**
     * @param _lp Pool that will happen the token swap
     * @param _amountOut Amount of tokens that we want as result of the swap
     * @param _tokenIn Received token
     * @param _tokenOut Wanted token
     * @return min amount of tokens with slippage applied
     */
    function getAmountIn(address _lp, uint256 _amountOut, address _tokenIn, address _tokenOut)
        external
        view
        returns (uint256)
    {
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(_lp, _tokenIn, _tokenOut);

        return UniswapV2Library.getAmountOut(_amountOut, reserveA, reserveB);
    }

    /**
     * @notice Get an estimation of token0 and token1 from breaking a given amount of LP
     * @param _lp LP token that will be used to simulate
     * @param _liquidityAmount Amount of LP tokens
     * @return Amount of token0
     * @return Amount of token1
     */
    function breakFromLiquidityAmount(address _lp, uint256 _liquidityAmount) public view returns (uint256, uint256) {
        uint256 totalLiquidity = IERC20(_lp).totalSupply();

        IERC20 _tokenA = IERC20(IUniswapV2Pair(_lp).token0());
        IERC20 _tokenB = IERC20(IUniswapV2Pair(_lp).token1());

        uint256 _amountA = (_tokenA.balanceOf(_lp) * _liquidityAmount) / totalLiquidity;
        uint256 _amountB = (_tokenB.balanceOf(_lp) * _liquidityAmount) / totalLiquidity;

        return (_amountA, _amountB);
    }

    /**
     * @notice Get estimation amount of LP tokens that will be received going from token0 or token1
     * @param _lp LP token that will be used to simulate
     * @param _tokenIn token0 or token1
     * @param _tokenAmount Amount of token0 or token1
     * @dev We dont verify it tokenIn is part of the LP because we do it in other parts of the code
     */
    function tokenToLiquidity(address _lp, address _tokenIn, uint256 _tokenAmount) public view returns (uint256) {
        (uint112 reserveA, uint112 reserveB,) = IUniswapV2Pair(_lp).getReserves();
        uint256 totalToken;

        if (_tokenIn == IUniswapV2Pair(_lp).token0()) {
            totalToken = reserveA;
        } else {
            totalToken = reserveB;
        }

        uint256 totalSupply = IERC20(_lp).totalSupply();

        return (totalSupply * _tokenAmount) / (totalToken * 2);
    }

    //////////////////////////////////////////////////////////
    //                  ASSETS PRICING
    //////////////////////////////////////////////////////////

    /**
     * @notice Returns wstETH price quoted in USD
     * @dev Returns value in 8 decimals
     */
    function wstEthPriceInUsd(uint256 amount) external view returns (uint256) {
        (, int256 stEthPrice,,,) = ST_ETH_ORACLE.latestRoundData();
        (, int256 wstEthRatio_,,,) = WST_ETH_ORACLE.latestRoundData();

        uint256 priceInEth = (uint256(stEthPrice) * uint256(wstEthRatio_)) / STANDARD_DECIMALS;

        return (amount * priceInEth) / STANDARD_DECIMALS;
    }

    /**
     * @notice Returns an arbitrary amount of wETH quoted in USD
     * @dev Returns value in 8 decimals
     */
    function ethPriceInUsd(uint256 amount) public view returns (uint256) {
        (, int256 ethPrice,,,) = ETH_ORACLE.latestRoundData();

        return (uint256(ethPrice) * amount) / STANDARD_DECIMALS;
    }

    /**
     * @notice Returns ETH price in USDC
     * @dev Returns value with 6 decimals
     */
    function ethPriceInUsdc(uint256 amount) external view returns (uint256) {
        uint256 ethPriceInUsd_ = ethPriceInUsd(amount * USDC_DECIMALS); // 8 + 6 decimals
        uint256 usdcPriceInUsd_ = usdcPriceInUsd(USDC_DECIMALS); // 8 decimals

        return ethPriceInUsd_ / usdcPriceInUsd_;
    }

    /**
     * @notice Returns wstETH quoted in ETH
     * @dev Returns value with 18 decimals
     */
    function wstEthRatio() external view returns (uint256) {
        (, int256 wstEthRatio_,,,) = WST_ETH_RATIO_ORACLE.latestRoundData();

        return uint256(wstEthRatio_);
    }

    /**
     * @notice Returns USD price of USDC
     * @dev Returns value with 8 decimals
     */
    function usdcPriceInUsd(uint256 amount) public view returns (uint256) {
        (, int256 usdcPrice,,,) = USDC_ORACLE.latestRoundData(); // 8 decimals

        return (uint256(usdcPrice) * amount) / USDC_DECIMALS;
    }

    /**
     * @notice Returns USDC price in ETH
     * @dev Returns value with 18 decimals
     */
    function usdcPriceInEth(uint256 amount) public view returns (uint256) {
        uint256 ethPriceInUsd_ = ethPriceInUsd(STANDARD_DECIMALS); // 8 decimals
        uint256 usdcPriceInUsd_ = usdcPriceInUsd(amount * STANDARD_DECIMALS); // 8 + 18 decimals

        return usdcPriceInUsd_ / ethPriceInUsd_; // 18 decimals
    }

    /**
     * @notice Returns the amount of 2crv that will be received from depositing given amount of USDC
     * @notice Since this is an unbalanced deposit, we may incur some positive or negative slippage
     * @dev 2crv = 18 decimals
     * @return 2crv amount that will be received
     */
    function get2CrvAmountFromDeposit(uint256 _usdcAmount) external view returns (uint256) {
        // First array element is USDC and second USDT, we pass it == true since its a deposit
        // Receive 2crv amount accounting for slippage but not fees
        return CRV.calc_token_amount([_usdcAmount, 0], true);
    }

    /**
     * @notice Returns amount of USDC that will be received by redeeming an amount of 2crv
     * @dev 6 decimals return
     * @return USDC amount
     */
    function getUsdcAmountFromWithdraw(uint256 _2crvAmount) public view returns (uint256) {
        return CRV.calc_withdraw_one_coin(_2crvAmount, 0);
    }

    function getUsdValueFromWithdraw(uint256 _2crvAmount) external view returns (uint256) {
        uint256 usdcAmount = getUsdcAmountFromWithdraw(_2crvAmount);

        return usdcPriceInUsd(usdcAmount);
    }
}

