// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IERC20.sol";

import "./IAggregationExecutor.sol";

interface IFireBirdRouter {
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    event Exchange(address pair, uint amountOut, address output);

    function factory() external view returns (address);

    function formula() external view returns (address);

    function WETH() external view returns (address);

    function swapFeeReward() external view returns (address);

    function addLiquidity(
        address pair,
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address pair,
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        address tokenIn,
        address tokenOut,
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        address tokenOut,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapTokensForExactETH(
        address tokenIn,
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForETH(
        address tokenIn,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapETHForExactTokens(
        address tokenOut,
        uint amountOut,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        address tokenOut,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address tokenIn,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external;

    function swap(
        IAggregationExecutor caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount);

    function createPair(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB,
        uint32 tokenWeightA,
        uint32 swapFee,
        address to
    ) external returns (uint liquidity);

    function createPairETH(
        address token,
        uint amountToken,
        uint32 tokenWeight,
        uint32 swapFee,
        address to
    ) external payable returns (uint liquidity);

    function removeLiquidity(
        address pair,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETH(
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function removeLiquidityWithPermit(
        address pair,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETHWithPermit(
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountToken, uint amountETH);

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountETH);
}

