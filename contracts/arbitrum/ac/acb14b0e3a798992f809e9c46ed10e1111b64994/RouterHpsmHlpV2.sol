// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./hPSM.sol";
import "./IRouter.sol";
import "./HlpRouterUtils.sol";
import "./BaseRouter.sol";
import "./HpsmUtils.sol";

/**
 * This contract:
 *     - swaps a pegged token in the handle.fi Peg Stability Module (hPSM) to
 *         a token (or ETH, if applicable) in the handle.fi Liquidity Pool (hLP)
 *     - swaps a token (or ETH) in the hLP for a pegged token in the hPSM
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
contract RouterHpsmHlpV2 is BaseRouter, HpsmUtils, HlpRouterUtils {
    using SafeERC20 for IERC20;

    constructor(address _hpsm, address _hlpRouter)
        HpsmUtils(_hpsm)
        HlpRouterUtils(_hlpRouter)
    {}

    /**
     * @notice Swaps a pegged token for a fx token.
     * @return the amount of fxToken available after swapping
     */
    function _swapPeggedTokenToFxToken(
        address peggedToken,
        address fxToken,
        uint256 amountIn
    ) internal returns (uint256) {
        // swap pegged token for fxToken
        _hpsmDeposit(peggedToken, fxToken, amountIn);
        // it is safe to use the balance here, as this contract should
        // not hold funds between calls
        return _balanceOfSelf(fxToken);
    }

    /**
     * @notice Swaps a fx token for a pegged token
     * @return the amount of pegged token available after swapping
     */
    function _swapFxTokenToPeggedToken(
        address fxToken,
        address peggedToken,
        uint256 amountIn
    ) internal returns (uint256) {
        // swap pegged token for fxToken
        _hpsmWithdraw(fxToken, peggedToken, amountIn);
        // it is safe to use the balance here, as this contract should
        // not hold funds between calls
        return _balanceOfSelf(peggedToken);
    }

    /**
     * @notice Swaps a pegged token for a hlpToken.
     * @dev this first swaps a pegged token for the fxToken it is pegged against,
     * then swaps the fxToken for the desired hlpToken using the hLP.
     */
    function swapPeggedTokenToHlpToken(
        address peggedToken,
        address fxToken,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        require(peggedToken != tokenOut, "Cannot convert to same token");
        require(fxToken != tokenOut, "Must use hPSM directly");

        _transferIn(peggedToken, amountIn);

        // swap pegged token to fx token
        uint256 fxTokenAmount = _swapPeggedTokenToFxToken(
            peggedToken,
            fxToken,
            amountIn
        );

        // approve router to access funds
        IERC20(fxToken).approve(hlpRouter, fxTokenAmount);

        address[] memory path = new address[](2);
        path[0] = fxToken;
        path[1] = tokenOut;

        // swap fx token to hlp token
        IRouter(hlpRouter).swap(
            path,
            fxTokenAmount,
            minOut,
            receiver,
            signedQuoteData
        );
    }

    /**
     * @notice Swaps a pegged token for a hlpToken.
     * @dev this first swaps a hlp token for the fx token in the hLP, then swaps
     * the fx token for the pegged token in the hPSM
     * @param hlpToken the token input
     * @param fxToken the intermediate step in the hPSM
     * @param tokenOut the pegged token in the hPSM, for the receiver to receive
     */
    function swapHlpTokenToPeggedToken(
        address hlpToken,
        address fxToken,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external {
        require(hlpToken != tokenOut, "Cannot convert to same token");
        require(fxToken != tokenOut, "Must use HlpRouter directly");

        _transferIn(hlpToken, amountIn);

        // approve router to access funds
        IERC20(hlpToken).approve(hlpRouter, amountIn);

        address[] memory path = new address[](2);
        path[0] = hlpToken;
        path[1] = fxToken;

        // swap hlp token to fx token
        IRouter(hlpRouter).swap(
            path,
            amountIn,
            0, // no min out needed, will be handled when transferring out
            _self,
            signedQuoteData
        );

        uint256 tokenOutAmount = _swapFxTokenToPeggedToken(
            fxToken,
            tokenOut,
            _balanceOfSelf(fxToken)
        );

        require(tokenOutAmount >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, tokenOutAmount);
    }

    /**
     * @notice Swaps a pegged token for ETH.
     * @dev this first swaps a pegged token for the fxToken it is pegged against,
     * then swaps the fxToken for ETH.
     */
    function swapPeggedTokenToEth(
        address peggedToken,
        address fxToken,
        uint256 amountIn,
        uint256 minOut,
        address payable receiver,
        bytes calldata signedQuoteData
    ) external {
        _transferIn(peggedToken, amountIn);

        // swap pegged token to fx token
        uint256 fxTokenAmount = _swapPeggedTokenToFxToken(
            peggedToken,
            fxToken,
            amountIn
        );

        // approve router to access funds
        IERC20(fxToken).approve(hlpRouter, fxTokenAmount);

        address[] memory path = new address[](2);
        path[0] = fxToken;
        path[1] = IRouter(hlpRouter).weth(); // router requires last element to be weth for eth swap

        // swap fx token to eth
        IRouter(hlpRouter).swapTokensToETH(
            path,
            fxTokenAmount,
            minOut,
            receiver,
            signedQuoteData
        );
    }

    /**
     * @notice Swaps a ETH for a pegged token.
     * @dev this first swaps eth for the fx token in the hLP, then swaps the fx token
     * for the pegged token in the hPSM
     * @param fxToken the intermediate step in the hPSM
     * @param tokenOut the pegged token in the hPSM, for the receiver to receive
     */
    function swapEthToPeggedToken(
        address fxToken,
        address tokenOut,
        uint256 minOut,
        address receiver,
        bytes calldata signedQuoteData
    ) external payable {
        require(fxToken != tokenOut, "Must use HlpRouter directly");
        require(msg.value > 0, "msg.value must not be zero");

        address[] memory path = new address[](2);
        path[0] = IRouter(hlpRouter).weth();
        path[1] = fxToken;

        // swap hlp token to fx token
        IRouter(hlpRouter).swapETHToTokens{value: msg.value}(
            path,
            0, // no min out needed, will be handled when transferring out
            _self,
            signedQuoteData
        );

        uint256 tokenOutAmount = _swapFxTokenToPeggedToken(
            fxToken,
            tokenOut,
            _balanceOfSelf(fxToken)
        );

        require(tokenOutAmount >= minOut, "Insufficient amount out");
        IERC20(tokenOut).safeTransfer(receiver, tokenOutAmount);
    }
}

