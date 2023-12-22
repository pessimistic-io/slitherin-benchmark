// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./ERC20.sol";
import "./BoringRebase.sol";
import "./Operatable.sol";
import "./ICauldronV2.sol";
import "./IBentoBoxV1.sol";

contract DegenBoxHelper is Operatable {
    using RebaseLibrary for Rebase;

    IBentoBoxV1 public immutable degenBox;
    IERC20 public immutable magicInternetMoney;

    constructor(IBentoBoxV1 degenBox_, IERC20 magicInternetMoney_) {
        degenBox = degenBox_;
        magicInternetMoney = magicInternetMoney_;
        degenBox_.registerProtocol();
    }

    function degenBoxDeposit(
        IERC20 token,
        address to,
        uint256 amount,
        uint256 share
    ) external payable onlyOperators returns (uint256, uint256) {
        return degenBox.deposit{value: msg.value}(token, tx.origin, to, amount, share);
    }

    function degenBoxWithdraw(
        IERC20 token,
        address to,
        uint256 amount,
        uint256 share
    ) external onlyOperators returns (uint256, uint256) {
        return degenBox.withdraw(token, tx.origin, to, amount, share);
    }

    /// @notice Repays a loan.
    /// @param to Address of the user this payment should go.
    /// @param cauldron cauldron on which it is repaid
    /// @param part The amount to repay. See `userBorrowPart`.
    /// @return amount The total amount repayed.
    function repayPart(
        address to,
        ICauldronV2 cauldron,
        uint256 part
    ) public onlyOperators returns (uint256 amount) {
        cauldron.accrue();
        
        Rebase memory totalBorrow = cauldron.totalBorrow();
        amount = totalBorrow.toElastic(part, true);

        uint256 share = degenBox.toShare(magicInternetMoney, amount, true);
        degenBox.transfer(magicInternetMoney, tx.origin, address(degenBox), share);
        cauldron.repay(to, true, part);
    }
}

