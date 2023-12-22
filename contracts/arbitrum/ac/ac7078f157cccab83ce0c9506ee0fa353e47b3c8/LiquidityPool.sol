// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LiquidityBox.sol";
import "./ILiquidityPool.sol";


/**
 * @title Liquidity Pool
 * @author Deepp Dev Team
 * @notice This is the liquidity provider contract that owns tokens.
 * @notice Tokens are deposited by users, that will receive LP tokens
 *         as proof-of-deposit.
 * @notice The depoisited tokens can be retrieved, by swapping the
 *         LP tokens back.
 * @notice LiquidityBox is Accesshandler, Accesshandler is Initializable.
 */
contract LiquidityPool is LiquidityBox, ILiquidityPool {

    constructor() LiquidityBox() {}

    /**
     * @notice Deposits tokens and updates the users locked amount.
     * @param tokenAdd The address of the token type to deposit.
     * @param amount The amount to add, including the fee.
     */
    function depositTokens(address tokenAdd, uint256 amount)
        external
        override
        whenNotPaused
        onlyAllowedToken(tokenAdd)
    {
        address owner = msg.sender;
        if (amount == 0) {
            emit DepositZero(owner, tokenAdd);
            return;
        }
        _deposit(owner, tokenAdd, amount);
    }

    /**
     * @notice Let the owner of deposited tokens withdraw them all again.
     * @param lpTokenAdd The lpToken type to return for the withdraw.
     */
    function withDrawAllTokens(address lpTokenAdd)
        external
        override
        whenNotPaused
    {
        address owner = msg.sender;
        uint256 lpTokenBalance = IERC20(lpTokenAdd).balanceOf(owner);
        if (lpTokenBalance == 0) {
            emit WithdrawZero(owner, lpTokenAdd);
            return;
        }
        _withdraw(owner, lpTokenAdd, lpTokenBalance);
    }

    /**
     * @notice Let the owner of deposited tokens withdraw them again.
     * @param lpTokenAdd The address of the lpToken type to return.
     * @param amount The amount of lpTokens to return.
     */
    function withDrawTokens(address lpTokenAdd, uint256 amount)
        external
        override
        whenNotPaused
    {
        address owner = msg.sender;
        _withdraw(owner, lpTokenAdd, amount);
    }
}

