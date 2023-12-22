// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IWETH.sol";
import "./IPancakeV3.sol";

interface ILogicContract {
    function addXTokens(
        address token,
        address xToken,
        uint8 leadingTokenType
    ) external;

    function approveTokenForSwap(address token) external;

    function claim(address[] calldata xTokens, uint8 leadingTokenType) external;

    function mint(address xToken, uint256 mintAmount)
        external
        returns (uint256);

    function borrow(
        address xToken,
        uint256 borrowAmount,
        uint8 leadingTokenType
    ) external returns (uint256);

    function repayBorrow(address xToken, uint256 repayAmount) external;

    function redeemUnderlying(address xToken, uint256 redeemAmount)
        external
        returns (uint256);

    function swapExactTokensForTokens(
        address swap,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        address swap,
        uint256 amountETH,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        address swap,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        address swap,
        uint256 amountETH,
        uint256 amountOut,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function addLiquidityETH(
        address swap,
        address token,
        uint256 amountTokenDesired,
        uint256 amountETHDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    )
        external
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidityETH(
        address swap,
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH);

    function addEarnToStorage(uint256 amount) external;

    function enterMarkets(address[] calldata xTokens, uint8 leadingTokenType)
        external
        returns (uint256[] memory);

    function returnTokenToStorage(uint256 amount, address token) external;

    function takeTokenFromStorage(uint256 amount, address token) external;

    function returnETHToMultiLogicProxy(uint256 amount) external;

    function deposit(
        address swapMaster,
        uint256 _pid,
        uint256 _amount
    ) external;

    function withdraw(
        address swapMaster,
        uint256 _pid,
        uint256 _amount
    ) external;

    function returnToken(uint256 amount, address token) external; // for StorageV2 only
}

/************* New Architecture *************/
interface ISwapLogic {
    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        bool isExactInput,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swap(
        address swapRouter,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        bool isExactInput,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

interface ILogic is ISwapLogic {
    function addEarnToStorage(uint256 amount) external;

    function returnTokenToStorage(uint256 amount, address token) external;

    function takeTokenFromStorage(uint256 amount, address token) external;

    function returnETHToMultiLogicProxy(uint256 amount) external;

    function multiLogicProxy() external view returns (address);

    function approveTokenForSwap(address _swap, address token) external;
}

interface ILendingLogic is ILogic {
    function isXTokenUsed(address xToken) external view returns (bool);

    function addXTokens(address token, address xToken) external;

    function comptroller() external view returns (address);

    function getAllMarkets() external view returns (address[] memory);

    function checkEnteredMarket(address xToken) external view returns (bool);

    function getUnderlyingPrice(address xToken) external view returns (uint256);

    function getUnderlying(address xToken) external view returns (address);

    function getXToken(address token) external view returns (address);

    function getCollateralFactor(address xToken)
        external
        view
        returns (uint256);

    function rewardToken() external view returns (address);

    function enterMarkets(address[] calldata xTokens)
        external
        returns (uint256[] memory);

    function claim() external;

    function mint(address xToken, uint256 mintAmount)
        external
        returns (uint256);

    function borrow(address xToken, uint256 borrowAmount)
        external
        returns (uint256);

    function repayBorrow(address xToken, uint256 repayAmount)
        external
        returns (uint256);

    function redeemUnderlying(address xToken, uint256 redeemAmount)
        external
        returns (uint256);

    function redeem(address xToken, uint256 redeemTokenAmount)
        external
        returns (uint256);

    function accrueInterest(address xToken) external;
}

interface IFarmingLogic is ILogic {
    function addLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function farmingDeposit(
        address swapMaster,
        uint256 _pid,
        uint256 _amount
    ) external;

    function farmingWithdraw(
        address swapMaster,
        uint256 _pid,
        uint256 _amount
    ) external;
}

struct BuildPairParams {
    address logic;
    address pool;
    uint256 token0Price;
    uint256 token1Price;
    uint24 minPricePercentage;
    uint24 maxPricePercentage;
    uint256 amountUsd;
}

struct ChangeLiquidityParams {
    address logic;
    address pool;
    uint256 token0Price;
    uint256 token1Price;
    int24 tickLower;
    int24 tickUpper;
    uint256 amountUsd;
}

struct AddLiquidityParams {
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
    int24 tickLower;
    int24 tickUpper;
    uint24 fee;
    uint256 tokenId;
}

struct RemoveLiquidityParams {
    uint256 tokenId;
    address pool;
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;
}

interface IFarmingV3Logic {
    function getAmountsByPosition(uint256 _tokenId, address _pool)
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidity
        );

    function calcFeeAmountsByPosition(uint256 _tokenId, address pool)
        external
        view
        returns (uint256 fee0, uint256 fee1);

    function getPositionInfo(uint256 _tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function addLiquidity(AddLiquidityParams memory params)
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function removeLiquidity(RemoveLiquidityParams memory params)
        external
        returns (uint256 amount0, uint256 amount1);

    function addToFarming(uint256 _tokenId) external;

    function removeFromFarming(uint256 _tokenId) external;

    function claimRewards(uint256 _tokenId) external returns (uint256);

    function rewardsToken() external view returns (address);

    function getRewardsAmount(uint256 _tokenId) external view returns (uint256);

    function burnPosition(uint256 _tokenId) external;

    function collectFees(uint256 _tokenId, address _pool)
        external
        returns (uint256 amount0, uint256 amount1);

    function WETH() external view returns (IWETH);

    function nftPositionManager()
        external
        view
        returns (INonfungiblePositionManager);

    function swapRouter() external view returns (IPancakeV3Router);

    function percentToTickDiff(uint24 percentDiff)
        external
        view
        returns (int24 tickDiff);

    function swapHelper(
        address swapRouter,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        bool isExactInput,
        uint256 deadline
    ) external payable;
}

