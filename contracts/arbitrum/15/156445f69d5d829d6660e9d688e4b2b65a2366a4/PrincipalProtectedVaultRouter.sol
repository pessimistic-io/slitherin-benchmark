// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./IVovoVault.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract PrincipalProtectedVaultRouter {
    using SafeERC20 for IERC20;

    address public upVault;
    address public downVault;
    address public vaultToken;

    event Deposit(address indexed depositor, address indexed account, uint256 upVaultAmount, uint256 downVaultAmount);
    event Withdraw(address indexed account, uint256 amount, uint256 upVaultShares, uint256 downVaultShare);

    constructor(address _upVault, address _downVault, address _vaultToken) public {
        upVault = _upVault;
        downVault = _downVault;
        vaultToken = _vaultToken;
    }

    function depositFor(uint256 upVaultAmount, uint256 downVaultAmount, address account) external {
        IVovoVault(upVault).depositFor(upVaultAmount, account);
        IVovoVault(downVault).depositFor(downVaultAmount, account);
        emit Deposit(msg.sender, account, upVaultAmount, downVaultAmount);
    }

    function withdraw(uint256 upVaultShares, uint256 downVaultShares) external {
        IVovoVault(upVault).withdraw(upVaultShares);
        IVovoVault(downVault).withdraw(downVaultShares);
        uint256 withdrawAmount = IERC20(vaultToken).balanceOf(address(this));
        IERC20(vaultToken).safeTransfer(msg.sender, withdrawAmount);
        emit Withdraw(msg.sender, withdrawAmount, upVaultShares, downVaultShares);
    }
}

