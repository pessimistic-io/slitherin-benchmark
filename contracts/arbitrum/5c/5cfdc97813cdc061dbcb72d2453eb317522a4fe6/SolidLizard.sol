// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";

interface ILizardRouter01 {

    struct Route {
        address from;
        address to;
        bool stable;
    }

    function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1);

    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);

    function quoteLiquidity(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);

    function getReserves(address tokenA, address tokenB, bool stable) external view returns (uint reserveA, uint reserveB);

    /// @dev Performs chained getAmountOut calculations on any number of pairs.
    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) external view returns (uint amount, bool stable);

    function getExactAmountOut(uint amountIn, address tokenIn, address tokenOut, bool stable) external view returns (uint);

    /// @dev Performs chained getAmountOut calculations on any number of pairs.
    function getAmountsOut(uint amountIn, Route[] memory routes) external view returns (uint[] memory amounts);

    function isPair(address pair) external view returns (bool);

    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired
    ) external view returns (uint amountA, uint amountB, uint liquidity);

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity
    ) external view returns (uint amountA, uint amountB);

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
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityMATIC(
        address token,
        bool stable,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountMATICMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountMATIC, uint liquidity);

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
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityMATIC(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountMATICMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountMATIC);

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
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityMATICWithPermit(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountMATICMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountMATIC);

    function removeLiquidityMATICSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountFTMMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountFTM);

    function removeLiquidityMATICWithPermitSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountFTMMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountFTM);

    function swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        Route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactMATICForTokens(uint amountOutMin, Route[] calldata routes, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function swapExactTokensForMATIC(uint amountIn, uint amountOutMin, Route[] calldata routes, address to, uint deadline)
    external
    returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        Route[] calldata routes,
        address to,
        uint deadline
    ) external;

    function swapExactMATICForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        Route[] calldata routes,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForMATICSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        Route[] calldata routes,
        address to,
        uint deadline
    ) external;

    function UNSAFE_swapExactTokensForTokens(
        uint[] memory amounts,
        Route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory);
}

interface ILizardPair is IERC20 {

    // Structure to capture time period obervations every 30 minutes, used for local oracles
    struct Observation {
        uint timestamp;
        uint reserve0Cumulative;
        uint reserve1Cumulative;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    function burn(address to) external returns (uint amount0, uint amount1);

    function mint(address to) external returns (uint liquidity);

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);

    function getAmountOut(uint, address) external view returns (uint);

    function claimFees() external returns (uint, uint);

    function tokens() external view returns (address, address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function stable() external view returns (bool);

    function metadata() external view returns (
        uint dec0,
        uint dec1,
        uint r0,
        uint r1,
        bool st,
        address t0,
        address t1
    );

    function skim(address to) external;

    function sync() external;

}

interface ILizardGauge {

    function depositAll(uint tokenId) external;

    function deposit(uint amount, uint tokenId) external;

    function withdrawAll() external;

    function withdraw(uint amount) external;

    function withdrawToken(uint amount, uint tokenId) external;

    function notifyRewardAmount(address token, uint amount) external;

    function getReward(address account, address[] memory tokens) external;

    function claimFees() external returns (uint claimed0, uint claimed1);

    function underlying() external view returns (address);

    function derivedSupply() external view returns (uint);

    function derivedBalances(address account) external view returns (uint);

    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function rewardTokens(uint id) external view returns (address);

    function isRewardToken(address token) external view returns (bool);

    function rewardTokensLength() external view returns (uint);

    function derivedBalance(address account) external view returns (uint);

    function left(address token) external view returns (uint);

    function earned(address token, address account) external view returns (uint);

    function tokenIds(address account) external view returns (uint);
}

interface ILizardBribe {

    function notifyRewardAmount(address token, uint amount) external;

    function _deposit(uint amount, uint tokenId) external;

    function _withdraw(uint amount, uint tokenId) external;

    function getRewardForOwner(uint tokenId, address[] memory tokens) external;

}

library SolidLizardLibrary {

    function getAmountsOut(
        ILizardRouter01 router,
        address inputToken,
        address outputToken,
        bool isStablePair0,
        uint256 amountInput
    ) internal view returns (uint256) {

        ILizardRouter01.Route[] memory routes = new ILizardRouter01.Route[](1);
        routes[0].from = inputToken;
        routes[0].to = outputToken;
        routes[0].stable = isStablePair0;

        return router.getAmountsOut(amountInput, routes)[1];
    }

    function getAmountsOut(
        ILizardRouter01 router,
        address inputToken,
        address middleToken,
        address outputToken,
        bool isStablePair0,
        bool isStablePair1,
        uint256 amountInput
    ) internal view returns (uint256) {

        ILizardRouter01.Route[] memory routes = new ILizardRouter01.Route[](2);
        routes[0].from = inputToken;
        routes[0].to = middleToken;
        routes[0].stable = isStablePair0;
        routes[1].from = middleToken;
        routes[1].to = outputToken;
        routes[1].stable = isStablePair1;

        return router.getAmountsOut(amountInput, routes)[2];
    }

    function singleSwap(
        ILizardRouter01 router,
        address inputToken,
        address outputToken,
        bool isStablePair0,
        uint256 amountInput,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256) {

        IERC20(inputToken).approve(address(router), amountInput);

        ILizardRouter01.Route[] memory routes = new ILizardRouter01.Route[](1);
        routes[0].from = inputToken;
        routes[0].to = outputToken;
        routes[0].stable = isStablePair0;

        return router.swapExactTokensForTokens(
            amountInput,
            amountOutMin,
            routes,
            recipient,
            block.timestamp
        )[1];
    }

    function multiSwap(
        ILizardRouter01 router,
        address inputToken,
        address middleToken,
        address outputToken,
        bool isStablePair0,
        bool isStablePair1,
        uint256 amountInput,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256) {

        IERC20(inputToken).approve(address(router), amountInput);

        ILizardRouter01.Route[] memory routes = new ILizardRouter01.Route[](2);
        routes[0].from = inputToken;
        routes[0].to = middleToken;
        routes[0].stable = isStablePair0;
        routes[1].from = middleToken;
        routes[1].to = outputToken;
        routes[1].stable = isStablePair1;

        return router.swapExactTokensForTokens(
            amountInput,
            amountOutMin,
            routes,
            recipient,
            block.timestamp
        )[2];
    }
}

