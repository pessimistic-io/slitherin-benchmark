// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IMetapoolFactory.sol";
import "./IStableSwap.sol";
import "./IRouter.sol";
import "./BaseRouter.sol";
import "./HpsmUtils.sol";
import "./RouterHpsmHlpV2.sol";

/**
 * This contract swaps a pegged token in the handle.fi Peg Stability Module (hPSM) to
 * a token in a specified handle curve metapool, via a token in the handle.fi
 * Liquidity Pool (hLP) if applicable.
 *
 * @dev safeApprove is intentionally not used, as since this contract should not store
 * funds between transactions, the approval race vulnerability does not apply.
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
contract RouterHpsmHlpCurve is BaseRouter, HpsmUtils {
    using SafeERC20 for IERC20;

    /** @notice Address of the handle.fi RouterHpsmHlp */
    address public routerHpsmHlp;

    event ChangeRouterHpsmHlp(address routerHpsmHlp);

    constructor(address _hpsm, address _routerHpsmHlp) HpsmUtils(_hpsm) {
        routerHpsmHlp = _routerHpsmHlp;
        emit ChangeRouterHpsmHlp(_routerHpsmHlp);
    }

    /** @notice Sets the address of the handle.fi RouterHpsmHlp */
    function setRouterHpsmHlp(address _routerHpsmHlp) external onlyOwner {
        require(routerHpsmHlp != _routerHpsmHlp, "Address already set");
        routerHpsmHlp = _routerHpsmHlp;
        emit ChangeRouterHpsmHlp(_routerHpsmHlp);
    }

    /**
     * @notice Swaps tokens in a curve.fi metapool
     * @param from the token to be sent
     * @param to the token to be received
     * @param amount the amount of {from} to send
     * @param metapoolFactory curve.fi metapool factory (the factory that deployed {pool})
     * @param pool The metapool that has {from} and {to} as either tokens or underlying tokens
     * @return the amount of {to} received from the swap
     */
    function _curvePoolSwap(
        address from,
        address to,
        uint256 amount,
        address metapoolFactory,
        address pool
    ) internal returns (uint256) {
        (
            int128 fromIndex,
            int128 toIndex,
            bool useUnderlying
        ) = IMetapoolFactory(metapoolFactory).get_coin_indices(pool, from, to);

        IERC20(from).approve(pool, amount);

        // min out is not handled here, which is why the last param is zero
        if (useUnderlying) {
            return
                IStableSwap(pool).exchange_underlying(
                    fromIndex,
                    toIndex,
                    amount,
                    0
                );
        }

        return IStableSwap(pool).exchange(fromIndex, toIndex, amount, 0);
    }

    /**
     * @notice swaps {peggedToken} for {curveToken}, using the hPSM and hLP (if applicable) as intermediate steps
     * @param peggedToken the pegged token in the hPSM to be sent
     * @param fxToken the token in the hPSM that is pegged against {peggedToken}
     * @param hlpToken the token received when swapping {fxToken} in the hLP
     * @dev if {fxToken} is the same as {hlpToken}, no swap between the two will occur
     * @param tokenOut the token received when swapping {hlpToken} in the curve.fi metapool.
     * This token will be sent to {receiver}
     * @param amountIn the amount of {peggedToken} to be sent
     * @param receiver the address that will receive {curveToken} at the end of the transaction
     * @param minOut the minimum amount of {curveToken} that will be sent to {receiver}
     * @dev If the amount out is less than {minOut}, the transaction will revert
     * @param metapoolFactory curve.fi metapool factory (the factory that deployed {pool})
     * @param pool The metapool that has {hlpToken} and {curveToken} as either tokens or underlying tokens
     * @param signedQuoteData The signed quote data to be sent to the handle.fi fast oracles
     * @dev {signedQuoteData} is only required if {fxToken} is not the same as {hlpToken}
     */
    function swapPeggedTokenToCurveToken(
        address peggedToken,
        address fxToken,
        address hlpToken,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        uint256 minOut,
        address metapoolFactory,
        address pool,
        bytes calldata signedQuoteData
    ) external {
        require(peggedToken != tokenOut, "Token in cannot be token out");
        require(amountIn > 0, "Amount in cannot be zero");

        _transferIn(peggedToken, amountIn); // transfer in funds

        if (fxToken == hlpToken) {
            // if fxToken and hlpToken are the same, only one swap in the
            // hpsm needs to be made
            _hpsmDeposit(peggedToken, fxToken, amountIn);
        } else {
            // use multi step router if fx token and hlp token are different
            IERC20(peggedToken).approve(routerHpsmHlp, amountIn);
            RouterHpsmHlpV2(routerHpsmHlp).swapPeggedTokenToHlpToken(
                peggedToken,
                fxToken,
                hlpToken,
                amountIn,
                0, // min out handled at end of function
                _self,
                signedQuoteData
            );
        }

        uint256 curveTokenAmountIn = _balanceOfSelf(hlpToken);
        _curvePoolSwap(
            hlpToken,
            tokenOut,
            curveTokenAmountIn,
            metapoolFactory,
            pool
        );

        uint256 amountOut = _balanceOfSelf(tokenOut);
        require(amountOut >= minOut, "Insufficient amount out");

        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }
}

