// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./Ownable.sol";
import "./hPSM.sol";
import "./IRouter.sol";

/**
 * This contract:
 *     - swaps a pegged token in the handle.fi Peg Stability Module (hPSM) to
 *         a token (or ETH, if applicable) in the handle.fi Liquidity Pool (hLP)
 *     - swaps a token (or ETH) in the hLP for a pegged token in the hPSM
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
contract RouterHpsmHlp is Ownable {
    address public hpsm;
    address public hlpRouter;
    address private immutable _self;

    event ChangeHpsm(address newPsm);
    event ChangeHlpRouter(address newHlpRouter);

    constructor(address _hpsm, address _hlpRouter) {
        hpsm = _hpsm;
        hlpRouter = _hlpRouter;
        _self = address(this);

        emit ChangeHpsm(hpsm);
        emit ChangeHlpRouter(hlpRouter);
    }

    /** @notice Sets the peg stability module address*/
    function setHpsm(address _hpsm) external onlyOwner {
        require(hpsm != _hpsm, "Address already set");
        hpsm = _hpsm;
        emit ChangeHpsm(hpsm);
    }

    /** @notice Sets the router address */
    function setHlpRouter(address _hlpRouter) external onlyOwner {
        require(hlpRouter != _hlpRouter, "Address already set");
        hlpRouter = _hlpRouter;
        emit ChangeHlpRouter(hlpRouter);
    }

    /** @notice Transfers in an ERC20 token */
    function _transferIn(address token, uint256 amount) internal {
        IERC20(token).transferFrom(msg.sender, _self, amount);
    }

    /** @return the {token} balance of this contract */
    function _balanceOfSelf(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(_self);
    }

    /**
     * @notice Deposits pegged token for fxToken in the hPSM
     * @param peggedToken the token to be deposited
     * @param fxToken the token to receive
     * @param amount the amount of {peggedToken} to deposit
     */
    function _hpsmDeposit(
        address peggedToken,
        address fxToken,
        uint256 amount
    ) internal {
        // approve hPSM for amount
        IERC20(peggedToken).approve(hpsm, amount);

        // deposit in hPSM
        hPSM(hpsm).deposit(fxToken, peggedToken, amount);
    }

    /**
     * @notice Withdraws peggedToken for fxToken in
     * @param fxToken the token to burn
     * @param peggedToken the token to receive
     * @param amount the amount of {fxToken} to burn
     */
    function _hpsmWithdraw(
        address fxToken,
        address peggedToken,
        uint256 amount
    ) internal {
        // No approval is needed as the hpsm can mint/burn fxtokens
        hPSM(hpsm).withdraw(fxToken, peggedToken, amount);
    }

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
        IERC20(tokenOut).transfer(receiver, tokenOutAmount);
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
        IERC20(tokenOut).transfer(receiver, tokenOutAmount);
    }
}

