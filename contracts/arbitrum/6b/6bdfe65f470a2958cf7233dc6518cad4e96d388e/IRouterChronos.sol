// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IRouterChronos {

    struct route {
        address from;
        address to;
        bool stable;
    }

  
    function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1) ;
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair) ;

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB, bool stable) external view returns (uint reserveA, uint reserveB) ;

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) external view returns (uint amount, bool stable) ;

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint amountIn, route[] memory routes) external view returns (uint[] memory amounts) ;

    function isPair(address pair) external view returns (bool) ;


    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired
    ) external view returns (uint amountA, uint amountB, uint liquidity) ;

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity
    ) external view returns (uint amountA, uint amountB) ;


    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external  returns (uint amountA, uint amountB, uint liquidity) ;

    function addLiquidityETH(
        address token,
        bool stable,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable  returns (uint amountToken, uint amountETH, uint liquidity) ;

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external  returns (uint amountA, uint amountB) ;

    function removeLiquidityETH(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external  returns (uint amountToken, uint amountETH) ;
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB) ;

    function removeLiquidityETHWithPermit(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH) ;

   

    function swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) ;

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) ;

    function swapExactETHForTokens(uint amountOutMin, route[] calldata routes, address to, uint deadline) external payable returns (uint[] memory amounts) ;

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, route[] calldata routes, address to, uint deadline)
    external
    returns (uint[] memory amounts);

    function UNSAFE_swapExactTokensForTokens(
        uint[] memory amounts,
        route[] calldata routes,
        address to,
        uint deadline
    ) external  returns (uint[] memory) ;





    // Experimental Extension [ETH.guru/solidly/BaseV1Router02]

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens)****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external  returns (uint amountToken, uint amountETH) ;
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH) ;
    
   
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external  ;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    )
        external
        payable
        ;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    )
        external
        
    ;
}
