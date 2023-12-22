// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IGMXRouter } from "./IGMXRouter.sol";
import { IGLPManager } from "./IGLPManager.sol";
import { IStrategy } from "./IStrategy.sol";
import { ISiloStrategy, ISiloLens, ISiloIncentiveController } from "./ISiloStrategy.sol";
import { ICamelot } from "./ICamelot.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

/**
 * @title GLPStrategy
 * @notice This contract is a strategy that interacts with the GMX protocol.
 * It automates certain actions such as minting GMX's GLP tokens, claiming fees, and charging performance fees.
 */
contract GLPStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;
    
    // Events
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 fee);

    address public glpRewardStorage;
    address public gmxRewardStorage;
    address public glpManager;
    address public gmxVault;
    address public rewardRouter;
    address public gmxRouter;

    /**
    * @notice Initialize the contract with initial values
    * @param _vaultAddress The address of vault
    * @param _assetAddress The address of asset
    * @param stratParams StratFeeManagerParams object
    * @param _gmxRouter The address of gmx router
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        address _gmxRouter,
        address _rewardRouter
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        gmxRouter = _gmxRouter;
        rewardRouter = _rewardRouter;
        glpRewardStorage = IGMXRouter(_rewardRouter).feeGlpTracker();
        gmxRewardStorage = IGMXRouter(_rewardRouter).feeGmxTracker();
        glpManager = IGMXRouter(gmxRouter).glpManager();
        gmxVault = IGLPManager(glpManager).vault();
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
        return _asset.balanceOf(address(this));
    }

    /**
    * @notice Performs the harvest operation before a deposit is made.
    */
    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == address(_vault), '!vault');
            _harvest(tx.origin);
        }
        beforeDepositBalance = _asset.balanceOf(address(this));
    }

    /**
    * @notice Function to manage deposit operation
    */
    function deposited() external nonReentrant whenNotPaused {
        afterDepositBalance = _asset.balanceOf(address(this));
        depositFeeCharge();
        emit Deposit(this.balanceOf());
    }

    function depositFeeCharge() internal {
        uint256 amount = afterDepositBalance - beforeDepositBalance;
        uint256 depositFeeAmount = amount.mul(depositFee).div(FEE_SCALE);
        _asset.safeTransfer(factorFeeRecipient, depositFeeAmount);
        emit DepositFeeCharge(depositFeeAmount);
    }

    /**
    * @notice Allows an external user to perform the harvest operation.
    */
    function harvest() external onlyKeeper nonReentrant {
        _harvest(tx.origin);
    }

    /**
    * @notice Performs the harvest operation, claiming rewards and swapping them to the input silo token.
    */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IGMXRouter(rewardRouter).compound();   
        IGMXRouter(rewardRouter).claimFees();
        uint256 bal = IERC20(weth).balanceOf(address(this));
        if (bal > 0) {
            chargeFees(callFeeRecipient);
            uint256 before = this.balanceOf();
            mintGlp();
            uint256 wantHarvested = this.balanceOf() - before;

            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, wantHarvested);
        }
    }

    function mintGlp() internal {
        uint256 balance = IERC20(weth).balanceOf(address(this));
        IGMXRouter(gmxRouter).mintAndStakeGlp(weth, balance, 0, 0);
    }

    /**
    * @notice Charges the performance fees after the harvest operation.
    */
    function chargeFees(address callFeeRecipient) internal {
        uint256 feeAmount = IERC20(weth).balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);

        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        IERC20(weth).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        IERC20(weth).safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        IERC20(weth).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, factorFeeAmount, strategistFeeAmount);
    }

    /**
    * @notice Withdraws the specified amount of tokens and sends them to the vault.
    * @param amount The amount of tokens to be withdrawn.
    */
    function withdraw(uint256 amount) external nonReentrant {
        require(msg.sender == address(_vault), '!vault');
        uint256 totalBalance = this.balanceOf();
        require(amount <= totalBalance, 'Insufficient total balance');
        //charge fee
        uint256 withdrawFeeAmount = amount.mul(withdrawFee).div(FEE_SCALE);
        _asset.safeTransfer(factorFeeRecipient, withdrawFeeAmount);
        uint256 withdrawAmount = amount.sub(withdrawFeeAmount);
        if (withdrawAmount > this.balanceOf()) {
            withdrawAmount = this.balanceOf();
        }
        _asset.safeTransfer(this.vault(), withdrawAmount);
        emit Withdraw(amount);
    }

    /**
    * @notice Exits the strategy by withdrawing all the assets.
    */
    function exit() external nonReentrant {
        require(msg.sender == address(_vault), "!vault");
        IGMXRouter(gmxRouter).unstakeAndRedeemGlp(weth, this.balanceOf(), 0, address(this));
        IERC20(weth).safeTransfer(this.vault(), IERC20(weth).balanceOf(address(this)));
    }  
    

    /**
    * @notice Emergency function to withdraw all assets and pause the strategy.
    */
    function panic() external onlyManager{
        _pause();
        _removeAllowances();
        IGMXRouter(gmxRouter).unstakeAndRedeemGlp(weth, this.balanceOf(), 0, address(this));
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
    * @notice Gives allowances to the silo pool and swap router for the silo asset and silo token.
    */
    function _giveAllowances() internal {
        IERC20(weth).safeApprove(glpManager, type(uint).max);
    }

    /**
    * @notice Removes allowances from the silo pool and swap router for the silo asset and silo token.
    */
    function _removeAllowances() internal {
        IERC20(weth).safeApprove(glpManager, 0);
    }

    /**
    * @notice Authorizes an upgrade of the strategy's implementation.
    * @param newImplementation The address of the new implementation.
    */
    function _authorizeUpgrade(address newImplementation) internal override {
        require(address(_vault) == msg.sender, 'Not vault!');
    }

    /**
     * @notice Sets the harvestOnDeposit flag and adjusts the withdrawal fee accordingly.
     * @param _harvestOnDeposit A boolean flag indicating whether to harvest on deposit or not.
     * If set to true, the withdrawal fee will be set to 0.
     * If set to false, the withdrawal fee will be set to 10000 (1%).
     */
    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawFee(0);
        } else {
            setWithdrawFee(10000);
        }
    }
}
