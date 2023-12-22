// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IBorrowerManager.sol";
import "./IBorrower.sol";
import "./LendVault.sol";
import "./UintArray.sol";

/**
 * @notice BorrowerManager contains logic to help the LendVault intereact with Borrowers,
 * as well as logic for updating the interest rates
 * @dev BorrowerManager is meant to be called by LendVault via delegateCall only
 * BorrowerManager follows the same inheritance chain as LendVault for this reason
 */
contract BorrowerManager is
    IBorrowerManager,
    ERC1155Upgradeable,
    AccessControl,
    BlockNonEOAUpgradeable,
    ReentrancyGuardUpgradeable,
    LendVaultStorage
{
    using SafeERC20 for IERC20;
    using AddressArray for address[];
    using UintArray for uint[];
    using Address for address;

    /**
     * @notice Event emitted when a borrower is killed when it becomes unhealthy
     */
    event Kill(address indexed borrower);

    /**
     * @notice Event emitted when a borrower needs to be delevered due to low liquidity in LendVault
     * @param borrower The borrower being deleveraged
     * @param token The token with low liquidity causing the deleveraging
     * @param amount The amount of the token that the borrower was able to provide by delevraging
     */
    event Delever(address indexed borrower, address indexed token, uint amount);

    /**
     * @notice Event emitted when a borrower is paused to repay all debts in event of low liquidity in LendVault
     * @param borrower The borrower being deleveraged
     * @param token The token with low liquidity causing the pause
     * @param amount The amount of the token that the borrower was able to provide by delevraging
     */
    event PauseBorrower(address indexed borrower, address indexed token, uint amount);

    /// @notice Private variable storing the address of the logic contract
    address private immutable self = address(this);

    /**
     * @notice Require that the current call is a delegatecall
     */
    function checkDelegateCall() private view {
        require(address(this) != self, "delegatecall only");
    }

    modifier onlyDelegateCall() {
        checkDelegateCall();
        _;
    }

    /// @inheritdoc IBorrowerManager
    function kill(address borrower) external onlyDelegateCall {
        address[] memory tokens = new address[](borrowerTokens[borrower].length);
        uint[] memory debts = new uint[](borrowerTokens[borrower].length);
        (address[] memory siezedTokens, uint[] memory siezedAmounts) = _siezeFunds(borrower);

        // Calculate and forgive existing debts
        for (uint i = 0; i<borrowerTokens[borrower].length; i++) {
            address token = borrowerTokens[borrower][i];
            tokens[i] = token;
            updateInterestRate(token);
            debts[i] = (debtShare[token][borrower] * tokenData[token].totalDebt) / Math.max(1, tokenData[token].totalDebtShares);

            // Forgive debt
            tokenData[tokens[i]].totalDebtShares-=debtShare[tokens[i]][borrower];
            debtShare[tokens[i]][borrower] = 0;
            tokenData[tokens[i]].totalDebt-=debts[i];

            // Remove from list of borrowers
            uint borrowerIndex = tokenBorrowers[token].findFirst(borrower);
            tokenBorrowers[token][borrowerIndex] = tokenBorrowers[token][tokenBorrowers[token].length-1];
            tokenBorrowers[token].pop();


            // Prevent further borrowing
            tokenData[token].totalCreditLimit-=creditLimits[tokens[i]][borrower];
            creditLimits[tokens[i]][borrower] = 0;
        }

        (debts, siezedAmounts) = _useSiezedFunds(SiezedFunds(tokens, debts, siezedTokens, siezedAmounts));

        // Return left overs to borrower and trigger deposit to re-enter liquidity position
        for (uint i = 0; i<siezedTokens.length; i++) {
            IERC20(siezedTokens[i]).safeTransfer(borrower, siezedAmounts[i]);
        }
        // IBorrower(borrower).deposit();

        // Clear list of borrowed tokens
        borrowerTokens[borrower] = new address[](0);
        
        // Request funds from reserve in case borrower was unable to repay entire debt
        for (uint i = 0; i<tokens.length; i++) {
            if (debts[i]>0) {
                uint amountReceived = IReserve(provider.reserve()).requestFunds(tokens[i], debts[i]);
                debts[i]-=amountReceived;
                tokenData[tokens[i]].lostFunds = debts[i];
            }
        }

        emit Kill(borrower);
    }

    /// @inheritdoc IBorrowerManager
    function delever(address token, uint amount) external onlyDelegateCall returns (uint tokensUsed){
        // Get list of borrowers of a token sorted by borrowed amount
        bytes memory data = address(this).functionStaticCall(abi.encodeWithSignature("getTokenBorrowers(address)", token));
        (address[] memory tokenBorrowers, uint[] memory amounts) = abi.decode(data, (address[], uint[]));
        (tokenBorrowers, amounts) = tokenBorrowers.sortDescending(amounts);

        // Delever borrowers in order of amount borrowed
        for (uint i = 0; i<tokenBorrowers.length; i++) {
            uint balanceBefore = ERC20(token).balanceOf(address(this));
            // Reentrancy check needs to be disabled here, in order to allow the borrower to call repay
            // No risk of attack exists here, since delever is only triggered from the withdraw function which blocks non EOA addresses
            _status = _NOT_ENTERED;
            IBorrower(tokenBorrowers[i]).delever(token, amount);
            uint balanceAfter = ERC20(token).balanceOf(address(this));
            if (amount>=(balanceAfter-balanceBefore)) {
                amount-=(balanceAfter-balanceBefore);
            } else {
                amount = 0;
            }
            emit Delever(tokenBorrowers[i], token, balanceAfter-balanceBefore);
        }

        // Force borrowers to repay debts completely if de-levering was insufficient
        if (amount>1) {
            for (uint i = 0; i<tokenBorrowers.length; i++) {
                uint balanceBefore = ERC20(token).balanceOf(address(this));
                // Reentrancy check needs to be disabled here, in order to allow the borrower to call repay
                // No risk of attack exists here, since delever is only triggered from the withdraw function which blocks non EOA addresses
                _status = _NOT_ENTERED;
                IBorrower(tokenBorrowers[i]).exit();
                uint balanceAfter = ERC20(token).balanceOf(address(this));
                if (amount>=(balanceAfter-balanceBefore)) {
                    amount-=(balanceAfter-balanceBefore);
                } else {
                    amount = 0;
                }
                emit PauseBorrower(tokenBorrowers[i], token, balanceAfter-balanceBefore);
            }
        }
        require(amount<=1, "E30");

        // Convert a few tokens to weth and send to keeper for gas fee
        _approve(provider.swapper(), token, 2**128);
        // We add 1 to tokenUsed, because of prior division inaccuracies leaving amount as 1, which ideally should be 0
        tokensUsed = ISwapper(provider.swapper()).swapTokensForExactTokens(token, deleverFeeETH, provider.networkToken(), slippage) + 1;
        IERC20(provider.networkToken()).safeTransfer(provider.keeper(), deleverFeeETH);
    }

    /// @inheritdoc IBorrowerManager
    function updateInterestRate(address token) public payable onlyDelegateCall {
        uint utilization =ILendVault(address(this)).utilizationRate(token);
        uint newInterestRate;

        if (utilization <= irmData[token].optimalUtilizationRate) {
            newInterestRate = irmData[token].baseBorrowRate + (irmData[token].slope1 * utilization) / irmData[token].optimalUtilizationRate;
        } else {
            newInterestRate = irmData[token].baseBorrowRate + irmData[token].slope1 + ((irmData[token].slope2 * (utilization - irmData[token].optimalUtilizationRate)) / (PRECISION - irmData[token].optimalUtilizationRate));
        }
        
        tokenData[token].totalDebt = ILendVault(address(this)).getTotalDebt(token);

        tokenData[token].interestRate = newInterestRate;
        tokenData[token].lastInterestRateUpdate = block.timestamp;
    }

    /**
     * @notice Sieze all the funds in possession of a borrower
     */
    function _siezeFunds(address borrower) internal returns (address[] memory, uint[] memory) {
        (address[] memory tokens, uint[] memory amounts) = IBorrower(borrower).getAmounts();
        uint[] memory balances = new uint[](amounts.length);
        for (uint i = 0; i<amounts.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        IBorrower(borrower).siezeFunds();
        for (uint i = 0; i<amounts.length; i++) {
            uint balanceNow = IERC20(tokens[i]).balanceOf(address(this));
            balances[i] = balanceNow-balances[i];
        }
        return (tokens, balances);
    }

    /**
     * @notice Uses siezed funds to repay debts
     * @dev siezedTokens that are the same as borrowedTokens are used first to repay the debts
     * @dev Then, leftover tokens are swapped to cover the remaining debts
     */
    function _useSiezedFunds(
        SiezedFunds memory siezedFunds
    ) internal returns (uint[] memory, uint[] memory) {
        // How much ETH can be used to repay the debt of each token
        uint[] memory allocableETH = new uint[](siezedFunds.borrowedTokens.length);
        {
            uint debtETHValue = ISwapper(provider.swapper()).getETHValue(siezedFunds.borrowedTokens, siezedFunds.debts);
            uint totalETHValue = ISwapper(provider.swapper()).getETHValue(siezedFunds.siezedTokens, siezedFunds.siezedAmounts);
            int health = (int(totalETHValue)-int(debtETHValue))*int(PRECISION)/ int(Math.max(1, debtETHValue));
            require(health<int(healthThreshold), "E32");

            // Repay debts for tokens that are already present in siezedFunds.siezedTokens
            for (uint i = 0; i<siezedFunds.debts.length; i++) {
                allocableETH[i] = ISwapper(provider.swapper()).getETHValue(siezedFunds.borrowedTokens[i], siezedFunds.debts[i])*totalETHValue/Math.max(1, debtETHValue);
                uint index = siezedFunds.siezedTokens.findFirst(siezedFunds.borrowedTokens[i]);

                // Check if siezedToken was found in borrowed tokens (siezedFunds.borrowedTokens)
                if (index<siezedFunds.siezedTokens.length) {
                    uint availableETH = ISwapper(provider.swapper()).getETHValue(siezedFunds.siezedTokens[index], siezedFunds.siezedAmounts[index]);
                    uint tokensUsed = Math.min(Math.min(
                        siezedFunds.debts[i],
                        allocableETH[i]*siezedFunds.siezedAmounts[index]/Math.max(1, availableETH)
                    ), siezedFunds.siezedAmounts[index]);
                    allocableETH[i]-=tokensUsed * availableETH / Math.max(1, siezedFunds.siezedAmounts[index]);
                    siezedFunds.siezedAmounts[index]-=tokensUsed;
                    siezedFunds.debts[i]-=tokensUsed;
                }
            }
        }
        return _swapAndUseLeftOvers(siezedFunds, allocableETH);
    }

    /**
     * @notice Swap siezed tokens to pay back borrower debts
     * @param siezedFunds Structure containing information about the funds available after siezing and debts that need to be paid
     * @param allocableETH Amount of ETH that is allocated to repaying the debt of each token in borrowedTokens
     * @return remainingDebts Debt amounts that the siezed tokens were unable to repay
     * @return leftovers Leftover siezed token amounts after repaying debts
     */
    function _swapAndUseLeftOvers(
        SiezedFunds memory siezedFunds,
        uint[] memory allocableETH
    ) internal returns (uint[] memory remainingDebts, uint[] memory leftovers) {
        // Iterate through every debt token and swap the siezed tokens to repay its debt
        for (uint i = 0; i<siezedFunds.debts.length; i++) {
            for (uint j = 0; j<siezedFunds.siezedTokens.length; j++) {

                uint availableETH = ISwapper(provider.swapper()).getETHValue(siezedFunds.siezedTokens[j], siezedFunds.siezedAmounts[j]);
                _approve(address(ISwapper(provider.swapper())), siezedFunds.siezedTokens[j], siezedFunds.siezedAmounts[j]);
                /**
                 * tokenUsed is the minimum of three values:
                 * - amountNeeded: The amount of siezed token needed to cover the debt completely
                 * - The amount of siezed tokens that can be allocated to repaying the debt
                 * - The amount of siezed token available
                 */
                uint tokensUsed = Math.min(Math.min(
                    ISwapper(provider.swapper()).getAmountIn(siezedFunds.siezedTokens[j], siezedFunds.debts[i], siezedFunds.borrowedTokens[i]),
                    allocableETH[i]*siezedFunds.siezedAmounts[j]/Math.max(1, availableETH)
                ), siezedFunds.siezedAmounts[j]);

                uint amountObtained = ISwapper(provider.swapper()).swapExactTokensForTokens(siezedFunds.siezedTokens[j], tokensUsed, siezedFunds.borrowedTokens[i], slippage);
                allocableETH[i]-=tokensUsed * availableETH / Math.max(1, siezedFunds.siezedAmounts[j]);
                siezedFunds.siezedAmounts[j]-=tokensUsed;
                siezedFunds.debts[i]-=Math.min(amountObtained, siezedFunds.debts[i]);
            }
        }

        // Return the debt amounts that couldn't be repaid as well as the leftover siezed tokens, if all debts were repaid
        remainingDebts = siezedFunds.debts;
        leftovers = siezedFunds.siezedAmounts;
    }

    /**
     * @notice Set approval to max for spender if approval isn't high enough
     */
    function _approve(address spender, address token, uint amount) internal {
        uint allowance = IERC20(token).allowance(address(this), spender);
        if(allowance<amount) {
            IERC20(token).safeIncreaseAllowance(spender, 2**256-1-allowance);
        }
    }
}
