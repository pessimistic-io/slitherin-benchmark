// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { ISiloStrategy, ISiloLens, ISiloIncentiveController } from "./ISiloStrategy.sol";
import { ICamelot } from "./ICamelot.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

contract SiloStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public siloAssetToDeposit;
    address public siloToken;

    // Third party contracts
    address public siloLens;
    address public siloIncentive;
    address public siloPool;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;
    
    // Events
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event DepositSilo(address indexed siloPool, uint256 indexed amount, uint256 indexed collateralAmount);
    event WithdrawSilo(address indexed siloPool, uint256 indexed amount, uint256 indexed collateralAmount);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    // Silo initialization parameters struct
    struct SiloInitParams {
        address siloAssetToDeposit;
        address siloPool;
        address siloLens;
        address siloIncentive;
        address siloToken;
    }

    /**
    * @notice Initializes the SiloStrategy contract with the provided parameters.
    * @param _vaultAddress The address of the vault contract.
    * @param _assetAddress The address of the asset (token) to be farmed.
    * @param stratParams StratFeeManagerParams struct with the required StratManager initialization parameters.
    * @param siloParams SiloInitParams struct with the required Silo initialization parameters.
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        SiloInitParams calldata siloParams
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        require(siloParams.siloLens != address(0), "Invalid siloLens address");
        require(siloParams.siloIncentive != address(0), "Invalid siloIncentive address");
        require(siloParams.siloToken != address(0), "Invalid siloToken address");
        require(siloParams.siloAssetToDeposit != address(0), "Invalid siloAssetToDeposit address");
        require(siloParams.siloPool != address(0), "Invalid siloPool address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        siloAssetToDeposit = siloParams.siloAssetToDeposit;
        siloPool = siloParams.siloPool;
        siloLens = siloParams.siloLens;
        siloIncentive = siloParams.siloIncentive;
        siloToken = siloParams.siloToken;
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
    * @notice Returns the address of the collateral token for the given silo.
    * @param silo The address of the silo.
    * @return The address of the collateral token.
    */
    function collateralTokenAddress(address silo) public view returns (address) {
        return ISiloStrategy(silo).assetStorage(siloAssetToDeposit).collateralToken;
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
    function balanceOfInputSiloToken() external view returns (uint256) {
        return IERC20(siloAssetToDeposit).balanceOf(address(this));
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
    * @notice Deposits the specified amount of tokens into the silo pool.
    * @param amount The amount of tokens to be deposited.
    */
    function _deposit(uint256 amount) internal whenNotPaused {
        (uint256 collateralAmount, ) = ISiloStrategy(siloPool).deposit(siloAssetToDeposit, amount, false);
        emit DepositSilo(siloPool, amount, collateralAmount);
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
        address[] memory assets = new address[](1);
        assets[0] = siloToken;
        ISiloIncentiveController(siloIncentive).claimRewards(assets, type(uint).max, address(this));
        uint256 siloTokenBal = IERC20(siloToken).balanceOf(address(this));
        if (siloTokenBal > 0) {
            // swap to usdc
            swapTokens(siloToken, siloAssetToDeposit, siloTokenBal);
            uint256 harvestedAmount = this.balanceOfInputSiloToken();
            chargeFees(callFeeRecipient);
            uint256 balanceInputSiloToken = this.balanceOfInputSiloToken();
            _deposit(balanceInputSiloToken);
            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, harvestedAmount);
        }
    }

    /**
    * @notice Charges the performance fees after the harvest operation.
    */
    function chargeFees(address callFeeRecipient) internal {
        uint256 feeAmount = IERC20(siloAssetToDeposit).balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);

        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        IERC20(siloAssetToDeposit).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        IERC20(siloAssetToDeposit).safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        IERC20(siloAssetToDeposit).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, factorFeeAmount, strategistFeeAmount);
    }

    /**
    * @notice Withdraws the specified amount of tokens from the silo pool.
    * @param amount The amount of tokens to be withdrawn.
    */
    function _withdraw(uint256 amount) internal {
        (uint256 collateralAmount, ) = ISiloStrategy(siloPool).withdraw(siloAssetToDeposit, amount, false);
        emit WithdrawSilo(siloPool, amount, collateralAmount);
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
        _withdrawAll();
        IERC20(siloAssetToDeposit).safeTransfer(this.vault(), this.balanceOfInputSiloToken());
    }  
    
    /**
    * @notice Withdraws all the assets from the silo pool.
    */
    function _withdrawAll() internal {
        _withdraw(type(uint256).max);
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
    * @notice Gives allowances to the silo pool and swap router for the silo asset and silo token.
    */
    function _giveAllowances() internal {
        IERC20(siloAssetToDeposit).safeApprove(siloPool, type(uint256).max);
        IERC20(siloToken).safeApprove(siloPool, type(uint256).max);
        IERC20(siloAssetToDeposit).safeApprove(swapRouter, type(uint256).max);
        IERC20(siloToken).safeApprove(swapRouter, type(uint256).max);
    }

    /**
    * @notice Removes allowances from the silo pool and swap router for the silo asset and silo token.
    */
    function _removeAllowances() internal {
        IERC20(siloAssetToDeposit).safeApprove(siloPool, 0);
        IERC20(siloToken).safeApprove(siloPool, 0);
        IERC20(siloAssetToDeposit).safeApprove(swapRouter, 0);
        IERC20(siloToken).safeApprove(swapRouter, 0);
    }
    
    /**
    * @notice Returns the unharvested rewards available.
    * @return The unharvested rewards amount.
    */
    function rewardsAvailable() public view returns (uint256) {
        return ISiloIncentiveController(siloIncentive).getUserUnclaimedRewards(address(this));
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
        address[] memory path = new address[](3);

        path[0] = _tokenIn;
        path[1] = weth;
        path[2] = _tokenOut;

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
