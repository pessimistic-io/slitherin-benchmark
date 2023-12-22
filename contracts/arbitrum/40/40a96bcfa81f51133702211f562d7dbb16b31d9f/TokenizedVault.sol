// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ProtocolFee.sol";
import "./ITokenizedVault.sol";
import "./Vault.sol";

abstract contract TokenizedVault is ITokenizedVault, Vault
{
    using SafeERC20 for IERC20;

    // =============================================================
    //                        Initialize
    // =============================================================
    constructor(address _depostiableToken) Vault(_depostiableToken) {
        
    }

    // =============================================================
    //                 External Functions
    // =============================================================
    function deposit(uint256 depositAmount)
        external
        virtual
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        require(depositAmount >= minDeposit() && depositAmount <= maxDeposit(), "INVALID_DEPOSIT_AMOUNT");

        _beforeDeposit(depositAmount);

        depositableToken.safeTransferFrom(msg.sender, address(this), depositAmount);

        require((shares = convertToShares(_processDepositAmount(depositAmount))) != 0, "ZERO_SHARES");

        _mint(msg.sender, shares);

        _afterDeposit(depositAmount, shares);

        emit Deposit(msg.sender, depositAmount, shares);
    }

    function withdraw(uint256 shares)
        external
        virtual
        whenNotPaused
        nonReentrant
        returns (uint256 amounts)
    {
        require(shares != 0, "ZERO_SHARES");
        require(balanceOf(msg.sender) >= shares, "INSUFFICIENT_SHARES");

        _beforeWithdraw(shares);

        amounts = _processWithdrawAmount(convertToAssets(shares));
        
        _burn(msg.sender, shares);

        emit Withdraw(msg.sender, shares, amounts);

        depositableToken.safeTransfer(msg.sender, amounts);

        _afterWithdraw(shares, amounts);
    }

    // =============================================================
    //                    INTERNAL HOOKS LOGIC
    // =============================================================
    function _beforeDeposit(uint256 depositAmount) internal virtual {}
    function _afterDeposit(uint256 depositAmount, uint256 shares) internal virtual {}
    function _beforeWithdraw(uint256 shares) internal virtual {}
    function _afterWithdraw(uint256 shares, uint256 withdrawAmount) internal virtual {}
}

