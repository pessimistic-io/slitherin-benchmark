// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./RouterHlpBalancer.sol";
import "./IWETH.sol";
import "./IRouter.sol";
import "./HlpRouterUtils.sol";
import "./BaseRouter.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract RouterEthHlpBalancer is BaseRouter, HlpRouterUtils {
    using SafeERC20 for IERC20;
    address public immutable routerHlpBalancer;

    constructor(address _routerHlpBalancer, address _hlpRouter)
        HlpRouterUtils(_hlpRouter)
    {
        routerHlpBalancer = _routerHlpBalancer;
    }

    /**
     * @dev Wraps msg.value from ETH to WETH and transfers it to {receiver}
     * @param weth the Wrapped Ether contract to use
     */
    function _wrapETH(address weth) private {
        IWETH(weth).deposit{value: msg.value}();
    }

    /**
     * @dev Wraps msg.value from ETH to WETH and transfers it to {receiver}
     * @param weth the Wrapped Ether contract to use
     */
    function _unwrapWETH(address weth) private {
        IWETH(weth).withdraw(_balanceOfSelf(weth));
    }

    /// @dev see {RouterHlpBalancer-swapBalancerToHlp}. The only difference is that since
    /// ETH is the 'token out', the {tokenOut} param is not required
    function swapBalancerToEth(
        address tokenIn,
        address hlpBalancerToken,
        bytes32 poolId,
        uint256 amountIn,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        address weth = IRouter(hlpRouter).weth();

        _transferIn(tokenIn, amountIn);
        IERC20(tokenIn).approve(routerHlpBalancer, amountIn);
        RouterHlpBalancer(routerHlpBalancer).swapBalancerToHlp(
            tokenIn,
            hlpBalancerToken,
            weth,
            poolId,
            amountIn,
            minOut,
            _self,
            signedQuoteData
        );

        _unwrapWETH(weth);
        require(_self.balance >= minOut, "Insufficient amount out");
        payable(receiver).transfer(_self.balance);
    }

    /// @dev see {RouterHlpBalancer-swapHlpToBalancer}. The only difference is that since
    /// ETH is the 'token in', the {tokenIn} and {amountIn} parameters are not required
    function swapEthToBalancer(
        address hlpBalancerToken,
        address tokenOut,
        bytes32 poolId,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external payable {
        address weth = IRouter(hlpRouter).weth();
        _wrapETH(weth);

        IERC20(weth).approve(routerHlpBalancer, msg.value);
        RouterHlpBalancer(routerHlpBalancer).swapHlpToBalancer(
            weth,
            hlpBalancerToken,
            tokenOut,
            poolId,
            msg.value,
            minOut,
            _self,
            signedQuoteData
        );

        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }

    receive() external payable {
        require(msg.sender == IRouter(hlpRouter).weth());
    }
}

