// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { IOlive } from "./IOlive.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

/**
 * @title OliveStrategy
 * @notice This contract is a strategy that interacts with the Plutus protocol.
 * 
 */
contract OliveStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public oliveVault;
    
    // Events
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    /**
    * @notice Initialize the contract with initial values.
    * @param _vaultAddress The address of the vault.
    * @param _assetAddress The address of the asset.
    * @param stratParams Parameters related to strategy fees.
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        address _oliveVault
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        oliveVault = _oliveVault;
        _giveAllowances();
    }

    /**
    * @notice Returns the address of the asset being farmed.
    * @return The address of the asset (token).
    */
    function asset() external view returns (address) {
        return address(_asset);
    }

    /**
    * @notice Returns the address of the vault contract.
    * @return The address of the vault contract.
    */
    function vault() external view returns (address) {
        return address(_vault);
    }

    /**
    * @notice Returns the balance of the asset held by the contract.
    * @return The balance of the asset.
    */
    function balanceOf() external view returns (uint256) {
        (uint256 balance , , , ) = IOlive(oliveVault).accountBalance(address(this));
        return _asset.balanceOf(address(this)) + balance;
    }

    /**
    * @notice Performs the harvest operation before a deposit is made.
    */
    function beforeDeposit() external {
    }

    /**
    * @notice Function to manage deposit operation
    */
    function deposited() external nonReentrant whenNotPaused{
        IOlive(oliveVault).deposit(_asset.balanceOf(address(this)));
        emit Deposit(this.balanceOf());
    }

    /**
    * @notice Allows an external user to perform the harvest operation.
    */
    function harvest() external nonReentrant whenNotPaused {
    }


    /**
    * @notice Withdraws the specified amount of tokens and sends them to the vault.
    * @param amount The amount of tokens to be withdrawn.
    */
    function withdraw(uint256 amount) external nonReentrant {
        require(msg.sender == address(_vault), "!vault");
        uint256 totalBalance = this.balanceOf();
        require(amount <= totalBalance, "Insufficient total balance");
        //charge fee
        IOlive(oliveVault).withdrawInstantly(amount);
        uint256 glpBalance = _asset.balanceOf(address(this));
        uint256 withdrawFeeAmount =  glpBalance.mul(withdrawFee).div(FEE_SCALE);
        IERC20(_asset).safeTransfer(factorFeeRecipient, withdrawFeeAmount);
        uint256 withdrawAmount = glpBalance - withdrawFeeAmount;
        IERC20(_asset).safeTransfer(this.vault(), withdrawAmount);

        emit Withdraw(this.balanceOf());
    }

    /**
    * @notice Exits the strategy by withdrawing all the assets.
    */
    function exit() external nonReentrant {
        require(msg.sender == address(_vault), "!vault");
        IOlive(oliveVault).withdrawInstantly(this.balanceOf());
        IERC20(_asset).safeTransfer(this.vault(), _asset.balanceOf(address(this)));
    }  
    

    /**
    * @notice Emergency function to withdraw all assets and pause the strategy.
    */
    function panic() external onlyManager{
        _pause();
        _removeAllowances();
    }

    /**
    * @notice Pauses the strategy and removes token allowances.
    */
    function pause() external onlyManager{
        _pause();
        _removeAllowances();
    }

    /**
    * @notice Unpauses the strategy and gives token allowances.
    */
    function unpause() external onlyManager{
        _unpause();
        _giveAllowances();
    }

    /**
    * @notice Gives allowances.
    */
    function _giveAllowances() internal {
        _asset.approve(oliveVault, type(uint256).max);
    }

    /**
    * @notice Removes allowances.
    */
    function _removeAllowances() internal {
        _asset.approve(oliveVault, 0);
    }

    /**
    * @notice Authorizes an upgrade of the strategy's implementation.
    * @param newImplementation The address of the new implementation.
    */
    function _authorizeUpgrade(address newImplementation) internal override {
        require(address(_vault) == msg.sender, 'Not vault!');
    }

}
