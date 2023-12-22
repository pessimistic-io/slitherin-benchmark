// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IBorrowerManager {

    /**
     * @notice Seize all the funds of a borrower to cover its debts and set its credit limit to 0
     * @dev Function will revert if the borrower's health is still above healthThreshold
     */
    function kill(address borrower) external;

    /**
     * @notice Reduce the leverage for the borrowers of a token in order to repay the token's lender
     * @dev Delevering will only bring the leverage down to an acceptable leverage
     * @dev If reducing leverage is insufficient, the borrowers will be asked to exit liquidity positions and completely repay debts
     * @dev Sends eth to keeper as gas fee to be used later for readjusting the strategy leverages
     * @return tokensUsed The amount of tokens used to obtain the gas fee
     */
    function delever(address token, uint amount) external returns (uint tokensUsed);

    /**
     * @notice Updates the token's totalDebt and interestRate and lastInterestRateUpdate
     * @dev Calculates the new interest rate using AAVE's interest rate model 
     * - https://docs.aave.com/risk/liquidity-risk/borrow-interest-rate
     * @dev Interest rate of token t, R_t follows the following model
     * - if U_t<=Uo_t:      R_t = R0_t + R_s1*(U_t/Uo_t)
     * - if U_t>Uo_t:       R_t = R0_t + R_s1 + R_s2*(U_t - Uo_t)/(1 - Uo_t)
     * - Where U_t is utilization of token t,
     * - Uo_t is optimial utilization rate of token t,
     * - R0_t is the base borrow rate of token t
     * - R_s1 is slope1 for token t
     * - R_s2 is slope2 for token t
     */
    function updateInterestRate(address token) external payable;
}
