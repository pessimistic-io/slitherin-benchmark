// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";
import { IPepePool } from "./IPepePool.sol";

/**
 * @title PepePool - $PEPE version
 */

contract PepePool is Ownable, IPepePool {
    IERC20 public immutable IPEPE;

    address public pepeBetAddress;
    address public serviceWallet;

    event UpdatedPepeBetAddress(address indexed oldAddress, address indexed newAddress);
    event Payout(address indexed user, uint256 indexed betId, uint256 amount);
    event FundedServiceWallet(address indexed serviceWallet, uint256 amount);
    event UpdatedServiceWallet(address indexed oldAddress, address indexed newAddress);
    event AdminWithdrawal(address indexed admin, uint256 amount);

    error NotPepeBet();
    error NotServiceWallet();
    error InvalidAddress();
    error WithdrawalFailed();
    error FundingServiceWalletFailed();
    error InsufficientFunds(uint256 requested, uint256 available);

    constructor(address _pepeAddress) {
        IPEPE = IERC20(_pepeAddress);
    }

    modifier onlyPepeBet() {
        if (msg.sender != pepeBetAddress) revert NotPepeBet();
        _;
    }

    modifier onlyServiceWallet() {
        if (msg.sender != serviceWallet) revert NotServiceWallet();
        _;
    }

    function payout(address user, uint256 amount, uint256 betId) external override onlyPepeBet {
        uint256 contractBalance = IPEPE.balanceOf(address(this));
        require(amount <= contractBalance, "PepePool: InsufficientFunds");
        bool success = IPEPE.transfer(pepeBetAddress, amount);
        require(success, "PepePool: PayoutFailed");
        emit Payout(user, betId, amount);
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

    function fundServiceWallet(uint256 amount) external override onlyServiceWallet {
        uint256 contractBalance = IPEPE.balanceOf(address(this));
        if (amount > contractBalance) revert InsufficientFunds(amount, contractBalance);
        bool success = IPEPE.transfer(serviceWallet, amount);
        if (!success) revert FundingServiceWalletFailed();
        emit FundedServiceWallet(serviceWallet, amount);
    }

    function withdraw(uint256 amount) external override onlyOwner {
        uint256 contractBalance = IPEPE.balanceOf(address(this));

        if (amount > contractBalance) revert InsufficientFunds(amount, contractBalance);
        bool success = IPEPE.transfer(owner(), amount);
        if (!success) revert WithdrawalFailed();
        emit AdminWithdrawal(owner(), amount);
    }
}

