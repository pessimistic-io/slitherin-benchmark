// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ISolidlyRouter.sol";

contract SolidlyRoutes {
    address public router;

    constructor(address _router){
        router = _router;
    }

    function swapToken(uint256 amount, ISolidlyRouter.Routes[] memory route) internal {
        if (route[0].from == route[0].to) return;
        ISolidlyRouter(router).swapExactTokensForTokens(amount, 0, route, address(this), block.timestamp);
    }

    function swapLpTokens(uint256 amount0, uint256 amount1, ISolidlyRouter.Routes[] memory route0, ISolidlyRouter.Routes[] memory route1) internal {
        swapToken(amount0, route0);
        swapToken(amount1, route1);
    }

    function removeLiquidity(address tokenA, address tokenB, bool isStable, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, uint256 deadline) internal returns (uint256 amountA, uint256 amountB) {
        return ISolidlyRouter(router).removeLiquidity(tokenA, tokenB, isStable, liquidity, amountAMin, amountBMin, address(this), deadline);
    }

    function addLiquidity(address tokenA, address tokenB, bool isStable, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, uint256 deadline) internal returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        return ISolidlyRouter(router).addLiquidity(tokenA, tokenB, isStable, amountADesired, amountBDesired, amountAMin, amountBMin, address(this), deadline);
    }

    function solidlyToUniRoute(ISolidlyRouter.Routes[] memory _route) internal pure returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }

    function setRouter(address _router) external {
        router = _router;
    }
}

