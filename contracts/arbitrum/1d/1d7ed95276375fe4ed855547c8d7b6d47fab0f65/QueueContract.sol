// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";
import {IErrors} from "./IErrors.sol";
import {IStrategyVault} from "./IStrategyVault.sol";

/// @notice Queue contract used to hold balances while vault has deployed funds to Y2K vaults
contract QueueContract is Ownable {
    /// @notice The balance of the user in the queue
    mapping(address => uint256) public balanceOf;

    /// @notice The deposit asset linking to each vault
    mapping(address => ERC20) public depositAsset;

    event DepositAssetSet(address strategyVault, address asset);
    event QueueDeposit(address caller, uint256 amount, address strategyVault);
    event DepositsCleared(address strategyVault, uint256 amount);

    //////////////////////////////////////////////
    //                 ADMIN - CONFIG           //
    //////////////////////////////////////////////
    /**
        @notice Set the deposit asset for a strategy vault 
        @dev Deposit asset being fetched by querying the strategy vault
        @param strategyVault The strategy vault to set the deposit asset for
     */
    function setDepositAsset(address strategyVault) external onlyOwner {
        ERC20 asset = IStrategyVault(strategyVault).asset();
        if (address(asset) == address(0)) revert IErrors.InvalidAsset();
        depositAsset[strategyVault] = asset;
        emit DepositAssetSet(strategyVault, address(asset));
    }

    //////////////////////////////////////////////
    //                   PUBLIC                 //
    //////////////////////////////////////////////
    /**
        @notice Transfers asset from the caller to the queue contract
        @dev Queued balance stored based on msg.sender i.e. strategyVault
        @param caller The caller of the function
        @param amount The amount to transfer
     */
    function transferToQueue(address caller, uint256 amount) external {
        ERC20 asset = depositAsset[msg.sender];
        if (address(asset) == address(0)) revert IErrors.InvalidAsset();
        balanceOf[msg.sender] += amount;
        asset.transferFrom(caller, address(this), amount);
        emit QueueDeposit(caller, amount, msg.sender);
    }

    /**
        @notice transfers assets from the queue contract to the caller (strategyVault)
        @dev Queued balance stored based on msg.sender i.e. strategyVault
     */
    function transferToStrategy() external {
        uint256 vaultBalance = balanceOf[msg.sender];
        if (vaultBalance == 0) revert IErrors.InsufficientBalance();
        delete balanceOf[msg.sender];
        depositAsset[msg.sender].transfer(msg.sender, vaultBalance);
        emit DepositsCleared(msg.sender, vaultBalance);
    }
}

