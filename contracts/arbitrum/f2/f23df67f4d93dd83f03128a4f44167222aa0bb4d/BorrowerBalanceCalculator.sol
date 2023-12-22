// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./IBorrower.sol";
import "./ISwapper.sol";
import "./ILendVault.sol";
import "./AddressArray.sol";
import "./UintArray.sol";
import "./Math.sol";

/**
 * @notice Common logic that is used by all Uniswap V3 strategies
 * @dev Non view functions should only be called via delegateCall
 */
contract BorrowerBalanceCalculator is AccessControl {
    using AddressArray for address[];
    using UintArray for uint[];

    function initialize(address _provider) external initializer {
        __AccessControl_init(_provider);
    }

    /**
     * @notice Calculate the balance of a borrower in terms of a token
     * @dev The returned value should be equal to what the borrower should have
     * after liquiditating uniswap pool position, repaying all debts and converting
     * all leftovers to the specified token
     * @dev the return value can be negative in case the borrower is unable to repay all
     * debts, indicating how much of the specified token is needed to cover all debts
     */
    function balanceInTermsOf(address token, address borrower) external view returns (int balance) {
        /* NOTE: SWAPPER CAN BE BROUGHT TO THE TOP OF THE CONTRACT AS IT IS IMPORTED IN OTHER FUNCTIONS*/
        ISwapper swapper = ISwapper(provider.swapper());
        
        address[] memory borrowedTokens; uint[] memory borrowedAmounts;
        address[] memory availableTokens; uint[] memory availableAmounts;


        (borrowedTokens, borrowedAmounts, availableTokens, availableAmounts) = _calculateDebtsAndLeftovers(borrower);

        // If any debt is greater than 0, availableAmounts will all be 0
        if (borrowedAmounts.sum()>0) {
            for (uint i = 0; i<borrowedTokens.length; i++) {
                balance-=int(swapper.getAmountIn(token, borrowedAmounts[i], borrowedTokens[i]));
            }
        } else {
            for (uint i = 0; i<availableTokens.length; i++) {
                balance+=int(swapper.getAmountOut(availableTokens[i], availableAmounts[i], token));
            }
        }

    }

    /**
     * @notice Calculate the unpaid debts and left over assets after liquidation and repayment
     * @dev If there is a non zero value in borrowedAmounts, availableAmounts will all be zero,
     * indicating a failure to repay all debts
     * @dev The calculation is broken into two parts, the first part (this function) repays all
     * debts that can be paid without swapping any tokens, the second part (_simulateSwapAndRepay)
     * Swaps the leftover tokens to repay the debts
     * @return borrowedTokens The tokens that the borrower has borrowed from LendVault
     * @return borrowedAmounts The size of the debts for each borrowed token
     * @return availableTokens The tokens leftover after repaying debts
     * @return availableAmounts the Amounts of the leftover tokens afte repaying debts
     */
    function _calculateDebtsAndLeftovers(
        address borrower
    ) public view returns (
        address[] memory borrowedTokens,
        uint[] memory borrowedAmounts,
        address[] memory availableTokens,
        uint[] memory availableAmounts
    ) {
        ILendVault lendVault = ILendVault(provider.lendVault());
        ISwapper swapper = ISwapper(provider.swapper());
        (borrowedTokens, borrowedAmounts) = lendVault.getBorrowerTokens(borrower);
        (availableTokens, availableAmounts) = IBorrower(borrower).getAmounts();

        // How much ETH can be used to repay the debt of each token
        uint[] memory allocableETH = new uint[](borrowedTokens.length);
        {
            uint debtETHValue = swapper.getETHValue(borrowedTokens, borrowedAmounts);
            uint totalETHValue = swapper.getETHValue(availableTokens, availableAmounts);

            // Repay debts for tokens that are already present in availableTokens
            for (uint i = 0; i<borrowedAmounts.length; i++) {
                allocableETH[i] = swapper.getETHValue(borrowedTokens[i], borrowedAmounts[i])*totalETHValue/Math.max(1, debtETHValue);
                uint index = availableTokens.findFirst(borrowedTokens[i]);

                // Check if siezedToken was found in borrowed tokens (borrowedTokens)
                if (index<availableTokens.length) {
                    uint availableETH = swapper.getETHValue(availableTokens[index], availableAmounts[index]);
                    uint tokensUsed = Math.min(Math.min(
                        borrowedAmounts[i],
                        allocableETH[i]*availableAmounts[index]/Math.max(1, availableETH)
                    ), availableAmounts[index]);
                    availableAmounts[index]-=tokensUsed;
                    borrowedAmounts[i]-=tokensUsed;
                    allocableETH[i]-=swapper.getETHValue(availableTokens[index], tokensUsed);
                }
            }
        }
        (borrowedAmounts, availableAmounts) = _simulateSwapAndRepay(
            SiezedFunds(
                borrowedTokens,
                borrowedAmounts,
                availableTokens,
                availableAmounts
            ),
            allocableETH
        );
    }

    function _simulateSwapAndRepay(
        SiezedFunds memory siezedFunds,
        uint[] memory allocableETH
    ) internal view returns (uint[] memory, uint[] memory) {
        ISwapper swapper = ISwapper(provider.swapper());
        // Iterate through every debt token and swap the siezed tokens to repay its debt
        for (uint i = 0; i<siezedFunds.debts.length; i++) {
            for (uint j = 0; j<siezedFunds.siezedTokens.length; j++) {
                uint availableETH = swapper.getETHValue(siezedFunds.siezedTokens[j], siezedFunds.siezedAmounts[j]);
                
                /**
                 * tokenUsed is the minimum of three values:
                 * - amountNeeded: The amount of siezed token needed to cover the debt completely
                 * - The amount of siezed tokens that can be allocated to repaying the debt
                 * - The amount of siezed token available
                 */
                uint tokensUsed = Math.min(Math.min(
                    swapper.getAmountIn(siezedFunds.siezedTokens[j], siezedFunds.debts[i], siezedFunds.borrowedTokens[i]),
                    allocableETH[i]*siezedFunds.siezedAmounts[j]/Math.max(1, availableETH)
                ), siezedFunds.siezedAmounts[j]);

                uint amountObtained = swapper.getAmountOut(siezedFunds.siezedTokens[j], tokensUsed, siezedFunds.borrowedTokens[i]);
                allocableETH[i]-=tokensUsed * availableETH / Math.max(1, siezedFunds.siezedAmounts[j]);
                siezedFunds.siezedAmounts[j]-=tokensUsed;
                siezedFunds.debts[i]-=Math.min(amountObtained, siezedFunds.debts[i]);
            }
        }

        return (siezedFunds.debts, siezedFunds.siezedAmounts);
    }
}
