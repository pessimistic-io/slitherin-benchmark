// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IBorrower {

    /**
     * @notice Returns the equity value of the strategy in terms of its stable token
     * @dev balance can be negative, indicating how much excess debt there is
     */
    function balance() external view returns (int balance);

    /**
     * @notice Returns cached balance if balance has previously been calculated
     * otherwise sets the cache with newly calculated balance
     */
    function balanceOptimized() external returns (int balance);

    /**
     * @notice Returns all the tokens in the borrower's posession after liquidating everything
     */
    function getAmounts() external view returns (address[] memory tokens, uint[] memory amounts);
    
    /**
     * @notice Returns all the tokens borrowed
     */
    function getDebts() external view returns (address[] memory tokens, uint[] memory amounts);

    /**
     * @notice Caluclates the pending fees harvestable from the 
     * uniswap pool in terms of the stable token
     */
    function getHarvestable() external view returns (uint harvestable);

    /**
     * @notice Fetches the pnl data for the strategy
     * @dev The data is calculated assuming an exit at the current block to realize all profits/losses
     * @dev The profits and losses are reported in terms of the vault's deposit token
     */
    function getPnl() external view returns (int pnl, int rewardProfit, int rebalanceLoss, int slippageLoss, int debtLoss, int priceChangeLoss);

    /**
     * @notice Fetch the token used for deposits by the strategy's vault
     */
    function getDepositToken() external view returns (address depositToken);

    /**
     * @notice Calculate the amount of tokens that can be deposited into the borrower
     * @dev amount is calculated based on the leverage and the LendVault's credit limits and available tokens
     */
    function getDepositable() external view returns (uint amount);

    /**
     * @notice Calculate the amonut of tokens to borrow from LendVault
     */
    function calculateBorrowAmounts() external view returns (address[] memory tokens, int[] memory amounts);

    /**
     * @notice Function to liquidate everything and transfer all funds to LendVault
     * @notice Called in case it is believed that the borrower won't be able to cover its debts
     * @return tokens Siezed tokens
     * @return amounts Amounts of siezed tokens
     */
    function siezeFunds() external returns (address[] memory tokens, uint[] memory amounts);

    /**
     * @notice Reduce leverage in order to pay back the specified debt
     * @param token Token that needs to be paid back
     * @param amount Amount of token that needs to be paid back
     */
    function delever(address token, uint amount) external;

    /**
     * @notice Exit liquidity position and repay all debts
     */
    function exit() external;

    /**
     * @notice Deposits all available funds into the appropriate liquidity position
     */
    function deposit() external;

    /**
     * @notice Permissioned function for controller to withdraw a token from the borrower
     */
    function withdrawOther(address token) external;

    /**
     * @notice Permissioned function called from controller or vault to withdraw to vault
     */
    function withdraw(uint256) external;

    /**
     * @notice Permissioned function called from controller or vault to withdraw all funds to vault
     */
    function withdrawAll() external;

    /**
     * @notice Harvest the rewards from the liquidity position, swap them and reinvest them
     */
    function harvest() external;
}
