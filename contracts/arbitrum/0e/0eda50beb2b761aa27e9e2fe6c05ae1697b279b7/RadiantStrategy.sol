// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { IRadiantLendingPool, IRadiantIncentive, IRadiantDataProvider } from "./IRadiant.sol";
import { ICamelot } from "./ICamelot.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { IVault, IAsset } from "./IBalancer.sol";
import { OracleLibrary } from "./OracleLibrary.sol";
import { IERC20Extended } from "./IERC20Extended.sol";

/**
 * @title RadiantStrategy
 * @dev A strategy for farming assets on Radiant. It includes functionalities for depositing, withdrawing,
 * harvesting, and managing assets. The strategy uses StratManager for managing fees and whitelisting,
 * ReentrancyGuard to prevent reentrancy attacks, and UUPSUpgradeable for contract upgrades.
 * @notice This contract should be used in conjunction with a vault contract.
 * For further information, check https://docs.radiant.capital/.
 */
contract RadiantStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant rtokenWethPool = 0x446BF9748B4eA044dd759d9B9311C70491dF8F29;
    address public constant wethUsdcPool = 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    bytes32 public constant balancerPool = 0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd;
    address public rAssetDeposit;
    address public rToken;

    // Third party contracts
    address public uniswaprDepositPool;
    address public rDataProvider;
    address public rIncentive;
    address public rPool;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    bool public balancerSwapActive;
    // Events
    event Deposit(address indexed rPool, uint256 indexed amount);
    event Withdraw(address indexed rPool, uint256 indexed amount);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);

    IVault public balancerVault;

    // Radiant initialization parameters structt
    struct RadiantInitParams {
        address rAssetDeposit;
        address rPool;
        address rDataProvider;
        address rIncentive;
        address rToken;
    }

    /**
     * @notice Initializes the RadiantStrategy contract with the provided parameters.
     * @param _vaultAddress The address of the vault contract.
     * @param _assetAddress The address of the asset (token) to be farmed.
     * @param stratParams StratFeeManagerParams struct with the required StratManager initialization parameters.
     * @param radiantParams RadiantInitParams struct with the required Radiant initialization parameters.
     */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        RadiantInitParams calldata radiantParams,
        address _balancerVault
    ) public initializer {
        require(_vaultAddress != address(0), 'Invalid vault address');
        require(_assetAddress != address(0), 'Invalid asset address');
        require(radiantParams.rAssetDeposit != address(0), 'Invalid rAssetDeposit address');
        require(radiantParams.rPool != address(0), 'Invalid rPool address');
        require(radiantParams.rDataProvider != address(0), 'Invalid rDataProvider address');
        require(radiantParams.rIncentive != address(0), 'Invalid rIncentive address');
        require(radiantParams.rToken != address(0), 'Invalid rToken address');
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        rAssetDeposit = radiantParams.rAssetDeposit;
        rPool = radiantParams.rPool;
        rDataProvider = radiantParams.rDataProvider;
        rIncentive = radiantParams.rIncentive;
        rToken = radiantParams.rToken;
        balancerVault = IVault(_balancerVault);
        balancerSwapActive = true;
        uniswaprDepositPool = wethUsdcPool;
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
     * @notice Returns the balance of the input silo token held by the contract.
     * @return The balance of the input silo token.
     */
    function balanceOfInputRDeposit() external view returns (uint256) {
        return IERC20(rAssetDeposit).balanceOf(address(this));
    }

    /**
     * @notice Performs the harvest operation before a deposit is made.
     */
    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == address(_vault), '!vault');
            _harvest(tx.origin);
        }
    }

    function deposited() external nonReentrant whenNotPaused {}

    /**
     * @notice Deposits the specified amount of tokens into the radiant pool.
     * @param amount The amount of tokens to be deposited.
     */
    function _deposit(uint256 amount) internal whenNotPaused {
        IRadiantLendingPool(rPool).deposit(rAssetDeposit, amount, address(this), 0);
        emit Deposit(rPool, amount);
    }

    /**
     * @notice Allows an external user to perform the harvest operation.
     */
    function harvest() external onlyKeeper nonReentrant {
        _harvest(tx.origin);
    }

    /**
     * @notice Performs the harvest operation, claiming rewards and swapping them to the input radiant token.
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        if (this.rewardsAvailable() > 0) {
            IRadiantIncentive(rIncentive).claimAll(address(this));
        }
        uint256 rTokenBal = IERC20(rToken).balanceOf(address(this));
        if (rTokenBal > 0) {
            // swap to usdc
            if (balancerSwapActive) {
                this.swapBalancer(balancerPool, rToken, rTokenBal, 0);
            } else {
                _swap(rToken, weth, rTokenBal, rtokenWethPool);
            }
            uint256 wethBal = IERC20(weth).balanceOf(address(this));
            _swap(weth, rAssetDeposit, wethBal, wethUsdcPool);
            uint256 harvestedAmount = this.balanceOfInputRDeposit();
            chargeFees(callFeeRecipient);
            uint256 balanceDeposit = this.balanceOfInputRDeposit();
            if (balanceDeposit > 0) {
                _deposit(balanceDeposit);
            }
            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, harvestedAmount);
        }
    }

    /**
     * @notice Charges the performance fees after the harvest operation.
     */
    function chargeFees(address callFeeRecipient) internal {
        uint256 feeAmount = IERC20(rAssetDeposit).balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);
        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        IERC20(rAssetDeposit).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        IERC20(rAssetDeposit).safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        IERC20(rAssetDeposit).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, factorFeeAmount, strategistFeeAmount);
    }

    /**
     * @notice Withdraws the specified amount of tokens from the lending pool.
     * @param amount The amount of tokens to be withdrawn.
     */
    function _withdraw(uint256 amount) internal {
        IRadiantLendingPool(rPool).withdraw(rAssetDeposit, amount, address(this));
        emit Withdraw(rPool, amount);
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
    }

    /**
     * @notice Exits the strategy by withdrawing all the assets.
     */
    function exit() external nonReentrant {
        require(msg.sender == address(_vault), '!vault');
        _withdraw(this.balanceOf());
        IERC20(rAssetDeposit).safeTransfer(this.vault(), this.balanceOfInputRDeposit());
    }

    function changeRouter(bool _balancerSwapActive) external onlyManager {
        balancerSwapActive = _balancerSwapActive;
    }

    function changeUniswaprDepositPool(address _uniswaprDepositPool) external onlyManager {
        uniswaprDepositPool = _uniswaprDepositPool;
    }

    /**
     * @notice Emergency function to withdraw all assets and pause the strategy.
     */
    function panic() external onlyManager {
        _withdraw(this.balanceOf());
        _pause();
        _removeAllowances();
    }

    /**
     * @notice Pauses the strategy and removes token allowances.
     */
    function pause() external onlyManager {
        _pause();
        _removeAllowances();
    }

    /**
     * @notice Unpauses the strategy and gives token allowances.
     */
    function unpause() external onlyManager {
        _unpause();
        _giveAllowances();
    }

    /**
     * @notice Gives allowances to the lending pool and swap router for the radiant asset and radiant token.
     */
    function _giveAllowances() internal {
        IERC20(rAssetDeposit).safeApprove(rPool, type(uint256).max);
        IERC20(rToken).safeApprove(rPool, type(uint256).max);
        IERC20(rAssetDeposit).safeApprove(swapRouter, type(uint256).max);
        IERC20(rToken).safeApprove(swapRouter, type(uint256).max);
    }

    /**
     * @notice Removes allowances from the lending pool and swap router for the radiant asset and radiant token.
     */
    function _removeAllowances() internal {
        IERC20(rAssetDeposit).safeApprove(rPool, 0);
        IERC20(rToken).safeApprove(rPool, 0);
        IERC20(rAssetDeposit).safeApprove(swapRouter, 0);
        IERC20(rToken).safeApprove(swapRouter, 0);
    }

    /**
     * @notice Returns the unharvested rewards available.
     * @return The unharvested rewards amount.
     */
    function rewardsAvailable() public view returns (uint256) {
        return IRadiantIncentive(rIncentive).allPendingRewards(address(this));
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

    /**
     * @notice Authorizes an upgrade of the strategy's implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        require(address(_vault) == msg.sender, 'Not vault!');
    }

    function getPrice(address tokenIn, address tokenOut, address pool) internal returns (uint256) {
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            pool,
            3600
        );

        return OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(10) ** IERC20Extended(tokenIn).decimals(),
            tokenIn,
            tokenOut
        );
    }

    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address pool
    ) internal returns (uint256) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);

        uint24 poolFee = 3000;
        // Get the expected output amount based on TWAP
        uint256 amountOutExpected = getPrice(tokenIn, tokenOut, pool);
         // Adjust the expected output by the input amount.
        // This is a simplified example and may not give the exact expected output, 
        // particularly for large trades that could significantly move the price.
        amountOutExpected = (amountOutExpected * amount) / (10**IERC20Extended(tokenIn).decimals());
        
        // Set the minimum accepted output amount to be example: 99% of the expected amount, allowing for 1% slippage
        uint256 amountOutMinimum = amountOutExpected.mul((slippage).div(SLIPPAGE_SCALE));
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        return ISwapRouter(swapRouter).exactInputSingle(params);
    }

    function swapBalancer(
        bytes32 _pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        // Construct the params for the swap
        IERC20(tokenIn).approve(address(balancerVault), amountIn);
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: _pool,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn),
            assetOut: IAsset(weth),
            amount: amountIn,
            userData: '0x'
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        uint256 deadline = block.timestamp; 

        // Perform the swap
        balancerVault.swap(singleSwap, funds, minAmountOut, deadline);
    }
}

