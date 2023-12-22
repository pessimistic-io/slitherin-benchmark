// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { IPepePool } from "./IPepePool.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepePool is IPepePool, Ownable2Step {
    using SafeERC20 for IERC20;
    address public pepeBetAddress;
    address public serviceWallet;

    event UpdatedPepeBetAddress(address indexed oldAddress, address indexed newAddress);
    event Payout(address indexed user, address betToken, uint256 indexed betId, uint256 amount);
    event FundedServiceWallet(address indexed serviceWallet, address indexed token, uint256 amount);
    event UpdatedServiceWallet(address indexed oldAddress, address indexed newAddress);
    event AdminWithdrawal(address indexed admin, address indexed token, uint256 amount);

    error NotPepeBet();
    error NotServiceWallet();
    error InvalidAddress();
    error WithdrawalFailed();
    error FundingServiceWalletFailed();
    error InsufficientFunds(uint256 requested, uint256 available);

    modifier onlyPepeBet() {
        if (msg.sender != pepeBetAddress) revert NotPepeBet();
        _;
    }

    modifier onlyServiceWallet() {
        if (msg.sender != serviceWallet) revert NotServiceWallet();
        _;
    }

    function payout(address user, address betToken, uint256 amount, uint256 betId) external override onlyPepeBet {
        uint256 contractBalance = IERC20(betToken).balanceOf(address(this));
        require(amount <= contractBalance, "PepePool: InsufficientFunds");
        IERC20(betToken).safeTransfer(pepeBetAddress, amount);
        emit Payout(user, betToken, betId, amount);
    }

    function setNewPepeBetAddress(address newPepeBet) external override onlyOwner {
        if (newPepeBet == address(0)) revert InvalidAddress();
        address oldPepeBet = pepeBetAddress;
        pepeBetAddress = newPepeBet;
        emit UpdatedPepeBetAddress(oldPepeBet, newPepeBet);
    }

    function setNewServiceWallet(address newServiceWallet) external override onlyOwner {
        if (newServiceWallet == address(0)) revert InvalidAddress();
        address oldServiceWallet = serviceWallet;
        serviceWallet = newServiceWallet;
        emit UpdatedServiceWallet(oldServiceWallet, newServiceWallet);
    }

    function fundServiceWallet(uint256 amount, address tokenAddress) external override onlyServiceWallet {
        uint256 contractBalance = IERC20(tokenAddress).balanceOf(address(this));
        if (amount > contractBalance) revert InsufficientFunds(amount, contractBalance);
        IERC20(tokenAddress).safeTransfer(serviceWallet, amount);
        emit FundedServiceWallet(serviceWallet, tokenAddress, amount);
    }

    function withdraw(uint256 amount, address tokenAddress) external override onlyOwner {
        uint256 contractBalance = IERC20(tokenAddress).balanceOf(address(this));

        if (amount > contractBalance) revert InsufficientFunds(amount, contractBalance);
        IERC20(tokenAddress).safeTransfer(owner(), amount);
        emit AdminWithdrawal(owner(), tokenAddress, amount);
    }
}

