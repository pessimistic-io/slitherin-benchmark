// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardChef {
    /**
     * @dev Returns true if the given token is whitelisted, otherwise returns false.
     * @param _token The address of the token to check.
     * @return A boolean value indicating whether the token is whitelisted or not.
     */
    function isWhitelisted(address _token) external view returns (bool);

    /**
     * @dev Swaps the given input token for UWU tokens and sends the output to the dynamic reward wallet.
     * @param _tokenIn The address of the input token.
     * @param _amountIn The amount of input tokens to swap.
     */
    function cookTokens(address _tokenIn, uint256 _amountIn) external;

    /**
     * @dev Withdraws the specified amount of UWU tokens to the owner.
     * @param _amount The amount of UWU tokens to withdraw.
     */
    function withdrawUWU(uint256 _amount) external;

    /**
     * @dev Withdraws the specified amount of a whitelisted token to the owner.
     * @param _token The address of the token to withdraw.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdrawToken(address _token, uint256 _amount) external;
}

