// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./BaseRouter.sol";
import "./HlpRouterUtilsV2.sol";
import "./IBalancerVault.sol";
import "./IRouter.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

/**
 * This contract:
 *     - swaps a hLP token to a token in a Balancer pool
 *     - swaps a token in a Balancer pool to a hLP token
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
contract RouterHlpBalancer is BaseRouter, HlpRouterUtilsV2 {
    using SafeERC20 for IERC20;

    address constant BALANCER_ETH = address(0);

    /** @notice the address of the balancer vault */
    address public immutable balancerVault;

    constructor(address _balancerVault, address _hlpRouter)
        HlpRouterUtilsV2(_hlpRouter)
    {
        balancerVault = _balancerVault;
    }

    /**
     * @dev swaps {from} for {to} in balancer pool with id {poolId}
     * @dev this function does not accept ETH swaps
     * @param from the token to send
     * @param to the token to receive
     * @param amount the amount of {from} to send
     * @param poolId the id of the balancer pool
     */
    function _swapBalancerTokens(
        address from,
        address to,
        uint256 amount,
        bytes32 poolId
    ) private {
        require(
            from != BALANCER_ETH && to != BALANCER_ETH,
            "ETH swap not directly permitted"
        );

        // from self, to self, using internal balance for neither
        IBalancerVault.FundManagement memory fundManagement = IBalancerVault
            .FundManagement(_self, false, payable(_self), false);
        // amount in is given, hence SwapKind.GIVEN_IN. No user data is needed, hence "0x00"
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(
            poolId,
            IBalancerVault.SwapKind.GIVEN_IN,
            from,
            to,
            amount,
            ""
        );

        // approve and perform swap
        IERC20(from).approve(balancerVault, amount);
        IBalancerVault(balancerVault).swap(
            singleSwap,
            fundManagement,
            0, // min out not handled in this function, so it is set to zero
            type(uint256).max // no deadline for this swap, hence deadline is infinite
        );
    }

    /**
     * @dev swaps {tokenIn} for {tokenOut} through the hLP, then balancer pool using {hlpBalancerToken}
     * as an intermediate token
     * @param tokenIn the token to be swapped for hlpBalancerToken in the hLP
     * @param hlpBalancerToken the token in both the hLP and Balancer pools to be
     * exchanged for {tokenOut} in balancer pool with id {poolId}
     * @param tokenOut the token to be sent to {receiver}
     * @param poolId the id of the balancer pool to be used
     * @param amountIn the amount of {tokenIn} to be sent
     * @param minOut the minimum amount of {tokenOut} that will be sent to receiver, otherwise
     * the transaction reverts
     * @param receiver the address that will receive {tokenOut}
     * @param signedQuoteData the price data to give to the hLP router
     */
    function swapHlpToBalancer(
        address tokenIn,
        address hlpBalancerToken,
        address tokenOut,
        bytes32 poolId,
        uint256 amountIn,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        require(tokenIn != tokenOut, "Token in cannot be token out");
        require(amountIn > 0, "Amount in cannot be zero");

        _transferIn(tokenIn, amountIn);

        // only swap in hLP if tokens are different
        if (tokenIn != hlpBalancerToken) {
            _hlpSwap(tokenIn, hlpBalancerToken, amountIn, signedQuoteData);
        }

        // swap {hlpBalancerToken} to {tokenOut} in the balancer pool of id {poolId}
        _swapBalancerTokens(
            hlpBalancerToken,
            tokenOut,
            _balanceOfSelf(hlpBalancerToken),
            poolId
        );

        // check min out
        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");

        // transfer out funds
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }

    /**
     * @dev swaps {tokenIn} for {tokenOut} through a balancer pool, then the hLP using {hlpBalancerToken}
     * as an intermediate token
     * @param tokenIn the token to be swapped for hlpBalancerToken in the balancer pool with id {poolId}
     * @param hlpBalancerToken the token in both the hLP and Balancer pools to be
     * exchanged for {tokenOut} in the hLP with id {poolId}
     * @param tokenOut the token to be sent to {receiver}
     * @param poolId the id of the balancer pool to be used
     * @param amountIn the amount of {tokenIn} to be sent
     * @param minOut the minimum amount of {tokenOut} that will be sent to receiver, otherwise
     * the transaction reverts
     * @param receiver the address that will receive {tokenOut}
     * @param signedQuoteData the price data to give to the hLP router
     */
    function swapBalancerToHlp(
        address tokenIn,
        address hlpBalancerToken,
        address tokenOut,
        bytes32 poolId,
        uint256 amountIn,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        require(tokenIn != tokenOut, "Token in cannot be token out");
        require(amountIn > 0, "Amount in cannot be zero");

        _transferIn(tokenIn, amountIn);

        _swapBalancerTokens(tokenIn, hlpBalancerToken, amountIn, poolId);

        // only swap in hLP if tokens are different
        if (hlpBalancerToken != tokenOut) {
            _hlpSwap(
                hlpBalancerToken,
                tokenOut,
                _balanceOfSelf(hlpBalancerToken),
                signedQuoteData
            );
        }

        // check min out
        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");

        // transfer out funds
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }
}

