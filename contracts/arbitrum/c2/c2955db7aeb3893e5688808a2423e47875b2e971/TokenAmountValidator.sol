// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

enum TokenAvailability { InsufficientBalance, InsufficientAllowance, OK }

/**
 * @title TokenAmountValidator
 * @author Deepp Dev Team
 * @notice Lib to help with checking token balances, allowance etc.
 */
library TokenAmountValidator {

    /** @notice Checks an address balance and allowance for a given amount.
     *  @param owner The owner of the token balance and allowance.
     *  @param amount Is amount to check for.
     *  @param tokenAddress The token to check the availability for.
     *  @param receiver The address to check allowance for.
     *  @return TokenAvailability enum value and balance available.
     */
    function checkAllowanceAndBalance(
        address owner,
        uint256 amount,
        address tokenAddress,
        address receiver
    )
        internal
        view
        returns (TokenAvailability, uint256)
    {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.allowance(owner, address(receiver));
        if ( balance < amount) {
            return (TokenAvailability.InsufficientAllowance, balance);
        }
        balance = token.balanceOf(owner);
        if (balance < amount) {
            return (TokenAvailability.InsufficientBalance, balance);
        }
        return (TokenAvailability.OK, balance);
    }

    /** @notice Checks an address allowance for a given amount.
     *  @param owner The owner of the token allowance.
     *  @param amount Is amount to check for.
     *  @param tokenAddress The token to check the availability for.
     *  @param receiver The address to check allowance for.
     *  @return TokenAvailability enum value and allowance available.
     */
    function checkAllowance(
        address owner,
        uint256 amount,
        address tokenAddress,
        address receiver
    )
        internal
        view
        returns (TokenAvailability, uint256)
    {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.allowance(owner, address(receiver));
        if (balance < amount) {
            return (TokenAvailability.InsufficientAllowance, balance);
        }
        return (TokenAvailability.OK, balance);
    }

    /** @notice Checks an address balance for a given amount.
     *  @param owner The owner of the token balance.
     *  @param amount Is amount to check for.
     *  @param tokenAddress The token to check the availability for.
     *  @return TokenAvailability enum value.
     */
    function checkBalance(
        address owner,
        uint256 amount,
        address tokenAddress
    )
        internal
        view
        returns (TokenAvailability, uint256)
    {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(owner);
        if (balance < amount) {
            return (TokenAvailability.InsufficientBalance, balance);
        }
        return (TokenAvailability.OK, balance);
    }
}

