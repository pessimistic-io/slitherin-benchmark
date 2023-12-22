// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IReserve {

    /**
     * @notice Returns the expected balance of the reserve in terms of USD
     * @dev balance includes both token balances as well as LendVault shares expressed
     * in terms of USD
     */
    function expectedBalance() external view returns (uint balance);

    /**
     * @notice Request made by LendVault to get funds for withdrawal from a lender in event of high utilization or borrowers defaulting
     * @return fundsSent Amount of tokens sent back
     */
    function requestFunds(address token, uint amount) external returns(uint fundsSent);

    /**
     * @notice Burn the shares that the reserve received from LendVault for assisting withdrawals during low liquidity
     */
    function burnLendVaultShares(address token, uint shares) external;

    /**
     * @notice Withdraw a specified amount of a token to the governance address
     */
    function withdraw(address token, uint amount) external;

    /**
     * @notice Sets the slippage variable to use while using swapper
     * @notice Swaps are performed if a token is requested but the reserve doesn't
     * have enough of the token
     */
    function setSlippage(uint _slippage) external;
}
