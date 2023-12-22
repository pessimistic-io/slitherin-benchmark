// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IGMXRouter } from "./IGMXRouter.sol";
import { IGLPManager } from "./IGLPManager.sol";
import { IStrategy } from "./IStrategy.sol";
import { IPlutusDepositor, IPlutusFarm } from "./IPlutus.sol";
import { ICamelot } from "./ICamelot.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

/**
 * @title PlutusStrategy
 * @notice This contract is a strategy that interacts with the Plutus protocol.
 * 
 */
contract PlutusStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    
    // Events
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    address public glpRewardStorage;
    address public gmxRewardStorage;
    address public glpManager;
    address public gmxVault;
    address gmxRouter;

    IPlutusDepositor plutusDepositor;
    IPlutusFarm plutusFarm;

    IERC20 public glp;
    IERC20 public sGlp;
    IERC20 public fsGlp;
    IERC20 public pls;
    IERC20 public plvGlp;

    /**
    * @notice Initialize the contract with initial values.
    * @param _vaultAddress The address of the vault.
    * @param _assetAddress The address of the asset.
    * @param stratParams Parameters related to strategy fees.
    * @param _gmxRouter The address of the GMX Router.
    * @param _plutusFarm The address of the Plutus Farm.
    * @param _plutusDepositor The address of the Plutus Depositor.
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        address _gmxRouter,
        address _plutusFarm,
        address _plutusDepositor
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        gmxRouter = _gmxRouter;
        glpRewardStorage = IGMXRouter(gmxRouter).feeGlpTracker();
        gmxRewardStorage = IGMXRouter(gmxRouter).feeGmxTracker();
        glpManager = IGMXRouter(gmxRouter).glpManager();
        gmxVault = IGLPManager(glpManager).vault();
        plutusDepositor = IPlutusDepositor(_plutusDepositor);
        plutusFarm = IPlutusFarm(_plutusFarm);
        sGlp = IERC20(plutusDepositor.sGLP());
        fsGlp = IERC20(plutusDepositor.fsGLP());
        pls = IERC20(plutusFarm.pls());
        plvGlp = IERC20(plutusDepositor.vault());
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
        plutusFarm.harvest();
        uint256 bal = pls.balanceOf(address(this));
        if (bal > 0) {
            chargeFees(callFeeRecipient);
            swapTokens(address(pls), weth, pls.balanceOf(address(this)));
            uint256 harvestAmount = IERC20(weth).balanceOf(address(this));
            _deposit();
            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, harvestAmount);
        }
    }
    
    /**
    * @notice Mints GLP and PLV-GLP tokens.
    */
    function _deposit() internal whenNotPaused {
        _mintGlp();
        _mintPlvGlp();
    }

    /**
    * @notice Mints GLP tokens using GMX Router.
    */
    function _mintGlp() internal {
        uint256 balance = IERC20(weth).balanceOf(address(this));
        IGMXRouter(gmxRouter).mintAndStakeGlp(weth, balance, 0, 0);
    }

    /**
    * @notice Mints PLV-GLP tokens using Plutus Depositor.
    */
    function _mintPlvGlp() internal {
        uint256 amount = sGlp.balanceOf(address(this));
        if (amount <= 0 ) return;
        plutusDepositor.deposit(amount);
    }

    /**
    * @notice Charges the performance fees after the harvest operation.
    */
    function chargeFees(address callFeeRecipient) internal {
        uint256 feeAmount = pls.balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);

        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        pls.safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        pls.safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        pls.safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, factorFeeAmount, strategistFeeAmount);
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
        uint256 withdrawFeeAmount =  amount.mul(withdrawFee).div(FEE_SCALE);
        IERC20(_asset).safeTransfer(factorFeeRecipient, withdrawFeeAmount);
        uint256 withdrawAmount = amount - withdrawFeeAmount;
        IERC20(_asset).safeTransfer(this.vault(), withdrawAmount);

        emit Withdraw(this.balanceOf());
    }

    /**
    * @notice Exits the strategy by withdrawing all the assets.
    */
    function exit() external nonReentrant {
        require(msg.sender == address(_vault), "!vault");
        IERC20(_asset).safeTransfer(this.vault(), this.balanceOf());
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
    * @notice Gives allowances to the silo pool and swap router for the silo asset and silo token.
    */
    function _giveAllowances() internal {
        IERC20(weth).safeApprove(glpManager, type(uint256).max);
        pls.safeApprove(swapRouter, type(uint256).max);
        sGlp.safeApprove(address(plutusDepositor), type(uint256).max);
    }

    /**
    * @notice Removes allowances from the silo pool and swap router for the silo asset and silo token.
    */
    function _removeAllowances() internal {
        IERC20(weth).safeApprove(glpManager, 0);
        pls.safeApprove(swapRouter, 0);
        sGlp.safeApprove(address(plutusDepositor), 0);
    }

    /**
    * @notice Authorizes an upgrade of the strategy's implementation.
    * @param newImplementation The address of the new implementation.
    */
    function _authorizeUpgrade(address newImplementation) internal override {
        require(address(_vault) == msg.sender, 'Not vault!');
    }

    /**
    * @notice Swaps tokens using the provided path.
    * @param _tokenIn The address of the input token.
    * @param _tokenOut The address of the output token.
    * @param _amountIn The amount of input tokens to be swapped.
    */
    function swapTokens(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal {
        address[] memory path = new address[](2);

        path[0] = _tokenIn;
        path[1] = _tokenOut;

        uint estimatedOutput = getEstimatedOutput(path, _amountIn);
        uint minTokenOutAmount = estimatedOutput.mul(slippage.div(SLIPPAGE_SCALE));

        ICamelot(swapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            minTokenOutAmount,
            path,
            address(this),
            address(0),
            block.timestamp
        );
    }

    function getEstimatedOutput(address[] memory path, uint _tokenInAmount) internal returns (uint) {
        uint[] memory amountsOut = ICamelot(swapRouter).getAmountsOut(_tokenInAmount, path);
        return amountsOut[amountsOut.length - 1];
    }
}
