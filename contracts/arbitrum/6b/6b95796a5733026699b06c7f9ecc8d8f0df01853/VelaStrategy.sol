// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { IVelaVault } from "./IVelaVault.sol";
import { IVelaTokenFarm } from "./IVelaTokenFarm.sol";
import { ICamelot } from "./ICamelot.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { OracleLibrary } from "./OracleLibrary.sol";
import { IERC20Extended } from "./IERC20Extended.sol";

contract VelaStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant velawethPool = 0x0cE541eAC2aDf14C8EEeB36D588A5DB21Df9e6C6;
    address public constant wethusdcPool = 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;

    address public velaToken;
    address public esVela;
    address public velaTokenFarm;
    address public velaVault;
    uint256 poolId;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;
    
    // Events
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event DepositVela(uint256 indexed amount);
    event WithdrawVela(uint256 indexed amount);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    // Vela initialization parameters struct
    struct VelaInitParams {
        address velaToken;
        address velaTokenFarm;
        address velaVault;
        address esVela;
        uint256 poolId;
    }

    /**
    * @notice Initializes the VelaStrategy contract with the provided parameters.
    * @param _vaultAddress The address of the vault contract.
    * @param _assetAddress The address of the asset (token) to be farmed.
    * @param stratParams StratFeeManagerParams struct with the required StratManager initialization parameters.
    * @param velaParams VelaInitParams struct with the required Vela initialization parameters.
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        VelaInitParams calldata velaParams
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        require(velaParams.velaTokenFarm != address(0), "Invalid velaTokenFarm address");
        require(velaParams.velaVault != address(0), "Invalid velaVault address");
        require(velaParams.velaToken != address(0), "Invalid velaToken address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        velaToken = velaParams.velaToken;
        velaTokenFarm = velaParams.velaTokenFarm;
        velaVault = velaParams.velaVault;
        esVela = velaParams.esVela;
        poolId = velaParams.poolId;
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
        require(msg.sender == address(_vault), '!vault');
        if (harvestOnDeposit) {
            _harvest(tx.origin);
        }
        beforeDepositBalance = _asset.balanceOf(address(this));
    }

    /**
    * @notice Function to manage deposit operation
    */
    function deposited() external nonReentrant whenNotPaused {
        require(msg.sender == address(_vault), '!vault');
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
    * @notice Deposits the specified amount of tokens into the vela vault.
    * @param amount The amount of tokens to be deposited.
    */
    function _deposit(uint256 amount) internal whenNotPaused {
        IVelaVault(velaVault).stake(address(this), usdc, amount);
        emit DepositVela(amount);
    }

    /**
    * @notice Allows an external user to perform the harvest operation.
    */
    function harvest() external nonReentrant {
        _harvest(tx.origin);
    }

    /**
    * @notice Performs the harvest operation, claiming rewards and swapping them to the input vela token.
    */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IVelaTokenFarm(velaTokenFarm).harvestMany(true, true, true, true);
        uint256 bal = IERC20(esVela).balanceOf(address(this));
        if (bal > 0) {
            IVelaTokenFarm(velaTokenFarm).depositVesting(bal);
        }
        if (IVelaTokenFarm(velaTokenFarm).claimable(address(this)) > 0) {
            IVelaTokenFarm(velaTokenFarm).withdrawVesting();
        }
        uint256 velaBalance = IERC20(velaToken).balanceOf(address(this));
        if (velaBalance > 0) {
            _swap(velaToken, weth, velaBalance, velawethPool);
            _swap(weth, usdc, IERC20(weth).balanceOf(address(this)), wethusdcPool);
            chargeFees(callFeeRecipient);
            uint256 harvestedAmount = IERC20(usdc).balanceOf(address(this));
            _deposit(harvestedAmount);
            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, harvestedAmount);
        }
    }

    /**
    * @notice Charges the performance fees after the harvest operation.
    */
    function chargeFees(address callFeeRecipient) internal {
        uint256 feeAmount = IERC20(usdc).balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);

        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        IERC20(usdc).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        IERC20(usdc).safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        IERC20(usdc).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, factorFeeAmount, strategistFeeAmount);
    }

    /**
    * @notice Withdraws the specified amount of tokens from the vela pool.
    * @param amount The amount of tokens to be withdrawn.
    */
    function _withdraw(uint256 amount) internal {
        IVelaVault(velaVault).unstake(usdc, amount);
        emit WithdrawVela(amount);
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
        _withdraw(this.balanceOf());
        IERC20(usdc).safeTransfer(this.vault(), IERC20(usdc).balanceOf(address(this)));
    }  
    

    /**
    * @notice Emergency function to withdraw all assets and pause the strategy.
    */
    function panic() external onlyManager{
        _withdraw(this.balanceOf());
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
    * @notice Gives allowances to the velaVault.
    */
    function _giveAllowances() internal {
        IERC20(velaToken).safeApprove(swapRouter, type(uint256).max);
        IERC20(weth).safeApprove(swapRouter, type(uint256).max);
        IERC20(usdc).safeApprove(velaVault, type(uint256).max);
    }

    /**
    * @notice Removes allowances from the velaVault.
    */
    function _removeAllowances() internal {
        IERC20(velaToken).safeApprove(swapRouter, 0);
        IERC20(weth).safeApprove(swapRouter, 0);
        IERC20(usdc).safeApprove(velaVault, 0);
    }
    
    function getPrice(address tokenIn, address tokenOut, address pool) internal returns (uint256) {
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(pool, 3600);

        return
            OracleLibrary.getQuoteAtTick(
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
}
