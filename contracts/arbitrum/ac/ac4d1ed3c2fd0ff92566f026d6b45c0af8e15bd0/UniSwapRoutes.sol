// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./UniswapV3Utils.sol";

abstract contract UniSwapRoutes is Ownable {
    using SafeERC20 for IERC20;

    struct Route {
        address[] aToBRoute;
        uint24[] aToBFees;
        bytes path;
    }

    mapping(address => Route) public routesByToken;
    address public router;
    address[] tokens;

    function swapReward(address token) internal {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            UniswapV3Utils.swap(router, routesByToken[token].path, tokenBalance);
        }
    }

    function registerRoute(address[] memory route, uint24[] memory fee) public onlyOwner {
        bytes memory path = UniswapV3Utils.routeToPath(route, fee);
        routesByToken[route[0]] = Route(route, fee, path);
        if (IERC20(route[0]).allowance(address(this), router) != type(uint).max) {
            IERC20(route[0]).safeApprove(router, type(uint).max);
        }
    }

    function setUniRouter(address _unirouter) public onlyOwner {
        router = _unirouter;
    }

    function setTokens(address[] memory _tokens) public onlyOwner {
        tokens = _tokens;
    }

    function swapRewards() internal {
        for (uint i = 0; i < tokens.length; i++) {
            swapReward(tokens[i]);
        }
    }
}

