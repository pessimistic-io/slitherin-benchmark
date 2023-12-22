// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LiquidityPool.sol";
import "./IBetLiquidityPool.sol";
import "./IERC20.sol";


/**
 * @title Bet Liquidity Pool
 * @author Deepp Dev Team
 * @notice This is the liquidity provider contract that owns tokens.
 * @notice Tokens are deposited by users, that will receive LP tokens
 *         as proof-of-deposit. Tokens can be used to match bets.
 * @notice The depoisited tokens can be retrieved, by swapping the
 *         LP tokens back.
 * @notice LiquidityPool is Accesshandler, Accesshandler is Initializable.
 */
contract BetLiquidityPool is LiquidityPool, IBetLiquidityPool {
    uint8 private maxLpBetPercent = 90;

    /**
     * @notice Event fires when bet percent limit is changed.
     * @param percent is the new limit.
     */
    event MaxLpBetPercent(
        uint8 percent
    );

    constructor() LiquidityPool() {}

    /**
     * @notice Transfer own tokens to betBox. To match our part of the bet.
     * @param tokenAdd The token type to transfer.
     * @param amount The amount to transfer.
     */
    function matchBet(
        address tokenAdd,
        uint256 amount
    )
        external
        override
        onlyAllowedToken(tokenAdd)
        onlyRole(BETTER_ROLE)
    {
        _moveToExt(tokenAdd, amount);
    }

    /**
     * @notice Sets the amount of fees to charge and distribute.
     * @param inLpBetPercent is the max percent of the full LP balance
     *        that can be used for bet matching.
     */
    function setLpBetPercent(uint8 inLpBetPercent)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (inLpBetPercent <= 100) {
            maxLpBetPercent = inLpBetPercent;
            emit MaxLpBetPercent(maxLpBetPercent);
        }
    }

    /**
     * @notice Return amount of tokens still available for bet matching.
     * @param tokenAdd The token type to check.
     * @return amount is available for bet matching.
     */
    function getLiquidityAvailableForBet(address tokenAdd)
        external
        override
        view
        returns (uint256 amount)
    {
        uint256 betLimit = getFullBalance(tokenAdd) * maxLpBetPercent / 100;
        uint256 betLocked = extLockBox.getLockedAmount(address(this), tokenAdd);
        if (betLimit > betLocked) {
            amount = getTokenBalance(tokenAdd);
            uint256 toLimit = betLimit - betLocked;
            if (amount > toLimit)
                amount = toLimit;
        } else {
            amount = 0;
        }
    }
}

