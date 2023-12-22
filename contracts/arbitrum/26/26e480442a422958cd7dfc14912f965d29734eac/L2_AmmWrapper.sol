// SPDX-License-Identifier: MIT

/***
 *      ______             _______   __                                             
 *     /      \           |       \ |  \                                            
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______  
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \ 
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *                                                                                  
 *                                                                                  
 *                                                                                  
 */
 
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import "./IWETH.sol";

interface ISwap {
    function swap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external returns (uint256);
}

interface IL2_Bridge {
    function send(
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 executorFee,
        uint256 amountOutMin,
        uint256 deadline
    ) external;
}

contract L2_AmmWrapper {

    IL2_Bridge public immutable bridge;
    IERC20 public immutable l2CanonicalToken;
    bool public immutable l2CanonicalTokenIsEth;
    IERC20 public immutable loopToken;
    ISwap public immutable exchangeAddress;

    /// @notice When l2CanonicalTokenIsEth is true, l2CanonicalToken should be set to the WETH address
    constructor(
        IL2_Bridge _bridge,
        IERC20 _l2CanonicalToken,
        bool _l2CanonicalTokenIsEth,
        IERC20 _loopToken,
        ISwap _exchangeAddress
    )
        public
    {
        bridge = _bridge;
        l2CanonicalToken = _l2CanonicalToken;
        l2CanonicalTokenIsEth = _l2CanonicalTokenIsEth;
        loopToken = _loopToken;
        exchangeAddress = _exchangeAddress;
    }

    receive() external payable {}

    /// @notice amount is the amount the user wants to send plus the Executor fee
    function swapAndSend(
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 executorFee,
        uint256 amountOutMin,
        uint256 deadline,
        uint256 destinationAmountOutMin,
        uint256 destinationDeadline
    )
        public
        payable
    {
        require(amount >= executorFee, "L2_AMM_W: Executor fee cannot exceed amount");

        if (l2CanonicalTokenIsEth) {
            require(msg.value == amount, "L2_AMM_W: Value does not match amount");
            IWETH(address(l2CanonicalToken)).deposit{value: amount}();
        } else {
            require(l2CanonicalToken.transferFrom(msg.sender, address(this), amount), "L2_AMM_W: TransferFrom failed");
        }

        require(l2CanonicalToken.approve(address(exchangeAddress), amount), "L2_AMM_W: Approve failed");
        uint256 swapAmount = exchangeAddress.swap(
            0,
            1,
            amount,
            amountOutMin,
            deadline
        );

        bridge.send(chainId, recipient, swapAmount, executorFee, destinationAmountOutMin, destinationDeadline);
    }

    function attemptSwap(
        address recipient,
        uint256 amount,
        uint256 amountOutMin,
        uint256 deadline
    )
        external
    {
        require(loopToken.transferFrom(msg.sender, address(this), amount), "L2_AMM_W: TransferFrom failed");
        require(loopToken.approve(address(exchangeAddress), amount), "L2_AMM_W: Approve failed");

        uint256 amountOut = 0;
        try exchangeAddress.swap(
            1,
            0,
            amount,
            amountOutMin,
            deadline
        ) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {}

        if (amountOut == 0) {
            // Transfer loopToken to recipient if swap fails
            require(loopToken.transfer(recipient, amount), "L2_AMM_W: Transfer failed");
            return;
        }

        if (l2CanonicalTokenIsEth) {
            IWETH(address(l2CanonicalToken)).withdraw(amountOut);
            (bool success, ) = recipient.call{value: amountOut}(new bytes(0));
            require(success, 'L2_AMM_W: ETH transfer failed');
        } else {
            require(l2CanonicalToken.transfer(recipient, amountOut), "L2_AMM_W: Transfer failed");
        }
    }
}

