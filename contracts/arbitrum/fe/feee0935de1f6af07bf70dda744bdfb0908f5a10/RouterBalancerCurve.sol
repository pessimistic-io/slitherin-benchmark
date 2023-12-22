// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./BaseRouter.sol";
import "./CurveUtils.sol";
import "./BalancerUtils.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

/**
 * @title RouterBalancerCurve
 * @notice swaps tokens through balancer and curve pools
 *
 *                ,.-"""-.,                       *
 *               /   ===   \                      *
 *              /  =======  \                     *
 *           __|  (o)   (0)  |__                  *
 *          / _|    .---.    |_ \                 *
 *         | /.----/ O O \----.\ |                *
 *          \/     |     |     \/                 *
 *          |                   |                 *
 *          |                   |                 *
 *          |                   |                 *
 *          _\   -.,_____,.-   /_                 *
 *      ,.-"  "-.,_________,.-"  "-.,             *
 *     /          |       |  ╭-╮     \            *
 *    |           l.     .l  ┃ ┃      |           *
 *    |            |     |   ┃ ╰━━╮   |           *
 *    l.           |     |   ┃ ╭╮ ┃  .l           *
 *     |           l.   .l   ┃ ┃┃ ┃  | \,         *
 *     l.           |   |    ╰-╯╰-╯ .l   \,       *
 *      |           |   |           |      \,     *
 *      l.          |   |          .l        |    *
 *       |          |   |          |         |    *
 *       |          |---|          |         |    *
 *       |          |   |          |         |    *
 *       /"-.,__,.-"\   /"-.,__,.-"\"-.,_,.-"\    *
 *      |            \ /            |         |   *
 *      |             |             |         |   *
 *       \__|__|__|__/ \__|__|__|__/ \_|__|__/    *
 */
contract RouterBalancerCurve is BaseRouter, CurveUtils, BalancerUtils {
    using SafeERC20 for IERC20;

    constructor(address balancerVault) BalancerUtils(balancerVault) {}

    /**
     * @dev swaps {tokenIn} for {tokenOut} through balancer, then curve
     * @param tokenIn the token to be sent, must be in the balancer pool
     * @param intermediateToken the token that will be swapped with {tokenIn} in the
     * balancer pool, then with {tokenOut} in the curve pool
     * @param tokenOut, the token to be sent to {receiver}, must be in the curve pool
     * @param curveFactory the factory that created the curve pool
     * @param curvePool the curve pool that contains {intermediateToken} and {tokenOut}
     * @param balancerPoolId the balancer pool that contains {tokenIn} and {intermediateToken}
     * @param amountIn the amount of {tokenIn} to be sent
     * @param minOut the minimum amount of {tokenOut} to be received
     * @param receiver the address that will receive {tokenOut}
     */
    function swapBalancerToCurve(
        address tokenIn,
        address intermediateToken,
        address tokenOut,
        address curveFactory,
        address curvePool,
        bytes32 balancerPoolId,
        uint256 amountIn,
        uint256 minOut,
        address receiver
    ) external {
        require(amountIn > 0, "Amount in cannot be zero");
        _transferIn(tokenIn, amountIn);

        _swapBalancerTokens(
            tokenIn,
            intermediateToken,
            amountIn,
            balancerPoolId
        );

        _swapCurveTokens(
            intermediateToken,
            tokenOut,
            _balanceOfSelf(intermediateToken),
            curveFactory,
            curvePool
        );

        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }

    /**
     * @dev swaps {tokenIn} for {tokenOut} through curve, then balancer
     * @param tokenIn the token to be sent, must be in the curve pool
     * @param intermediateToken the token that will be swapped with {tokenIn} in the
     * curve pool, then with {tokenOut} in the balancer pool
     * @param tokenOut, the token to be sent to {receiver}, must be in the balancer pool
     * @param curveFactory the factory that created the curve pool
     * @param curvePool the curve pool that contains {intermediateToken} and {tokenIn}
     * @param balancerPoolId the balancer pool that contains {tokenOut} and {intermediateToken}
     * @param amountIn the amount of {tokenIn} to be sent
     * @param minOut the minimum amount of {tokenOut} to be received
     * @param receiver the address that will receive {tokenOut}
     */
    function swapCurveToBalancer(
        address tokenIn,
        address intermediateToken,
        address tokenOut,
        address curveFactory,
        address curvePool,
        bytes32 balancerPoolId,
        uint256 amountIn,
        uint256 minOut,
        address receiver
    ) external {
        require(amountIn > 0, "Amount in cannot be zero");
        _transferIn(tokenIn, amountIn);

        _swapCurveTokens(
            tokenIn,
            intermediateToken,
            amountIn,
            curveFactory,
            curvePool
        );

        _swapBalancerTokens(
            intermediateToken,
            tokenOut,
            _balanceOfSelf(intermediateToken),
            balancerPoolId
        );

        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }
}

