// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./RouterHlpBalancer.sol";
import "./Hpsm2Utils.sol";
import "./BaseRouter.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract RouterHpsmHlpBalancer is BaseRouter, Hpsm2Utils {
    using SafeERC20 for IERC20;
    address public immutable routerHlpBalancer;

    constructor(address _routerHlpBalancer, address _hpsm) Hpsm2Utils(_hpsm) {
        routerHlpBalancer = _routerHlpBalancer;
    }

    /**
     * @dev swaps {peggedToken} for {tokenOut} by
     *     - swapping {peggedToken} for {fxToken} in the hPSM
     *     - swapping {fxToken} for {tokenOut} in RouterHlpBalancer
     * @param peggedToken the token to be sent, must be a pegged token in the hPSM
     * @param fxToken the token to be swapped for {peggedToken} in the hPSM. Must be in the hLP
     * @param hlpBalancerToken the token to be swapped with {fxToken} in the hLP, if it differs
     * from {fxToken}. Must be in both the hLP and balancer pool with {poolId}
     * @param tokenOut the token to be swapped for {hlpBalancerToken} in the balancer pool
     * with id {poolId}.
     * @param amountIn the amount of {peggedToken} to send
     * @param minOut the minimum amount of {tokenOut} to be sent to receiver
     * @param poolId the balancer pool for which to swap {hlpBalancerToken} with {tokenOut}
     * @param receiver the address that receives {tokenOut}
     * @param signedQuoteData the signed quote data to be given to the hLP Router
     */
    function swapPeggedTokenToBalancer(
        address peggedToken,
        address fxToken,
        address hlpBalancerToken,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        bytes32 poolId,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        require(peggedToken != tokenOut, "Token in cannot be token out");
        require(amountIn > 0, "Amount in cannot be zero");
        _transferIn(peggedToken, amountIn);

        _hpsmDeposit(peggedToken, fxToken, amountIn);
        uint256 hpsmAmountOut = _balanceOfSelf(fxToken);

        IERC20(fxToken).approve(routerHlpBalancer, hpsmAmountOut);
        RouterHlpBalancer(routerHlpBalancer).swapHlpToBalancer(
            fxToken,
            hlpBalancerToken,
            tokenOut,
            poolId,
            hpsmAmountOut,
            minOut,
            _self,
            signedQuoteData
        );

        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }

    /**
     * @dev swaps {tokenIn} for {tokenOut} by
     *     - swapping {tokenIn} for {fxToken} in RouterHlpBalancer
     *     - swapping {fxToken} for {tokenOut} in the hPSM
     * @param tokenIn the token to send, must be in the balancer pool
     * @param hlpBalancerToken the token to be swapped with {tokenIn}. Must be in both the hLP
     * and the balancer pool with id {poolId}
     * @param fxToken the token to be swapped with {hlpBalancerToken} in the hLP, if they are
     * different. Must also be in the hPSM.
     * @param tokenOut the token to be swapped with fxToken in the hPSM. Must be a pegged token in
     * the hPSM
     * @param amountIn the amount of {tokenIn} to send
     * @param minOut the minimum amount of {tokenOut} to be sent to receiver
     * @param poolId the balancer pool for which to swap {tokenIn} with {fxToken}
     * @param receiver the address that receives {tokenOut}
     * @param signedQuoteData the signed quote data to be given to the hLP Router
     */
    function swapBalancerToPeggedToken(
        address tokenIn,
        address hlpBalancerToken,
        address fxToken,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        bytes32 poolId,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        require(tokenIn != tokenOut, "Token in cannot be token out");
        require(amountIn > 0, "Amount in cannot be zero");
        _transferIn(tokenIn, amountIn);

        IERC20(tokenIn).approve(routerHlpBalancer, amountIn);
        RouterHlpBalancer(routerHlpBalancer).swapBalancerToHlp(
            tokenIn,
            hlpBalancerToken,
            fxToken,
            poolId,
            amountIn,
            minOut,
            _self,
            signedQuoteData
        );

        _hpsmWithdraw(fxToken, tokenOut, _balanceOfSelf(fxToken));

        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }
}

