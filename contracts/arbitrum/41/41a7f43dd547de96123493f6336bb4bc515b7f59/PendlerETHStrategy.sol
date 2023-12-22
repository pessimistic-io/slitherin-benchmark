// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { IPendleMarket, IPendleRouter } from "./IPendle.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { IVault, IAsset } from "./IBalancer.sol";

/**
 * @title PendlerETHStrategy
 * @notice This contract is a strategy that interacts with the Pendle protocol.
 * 
 */
contract PendlerETHStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant reth = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
    address public constant bbweth = 0xDa1CD1711743e57Dd57102E9e61b75f3587703da;
    bytes32 public constant rethpool = 0xcba9ff45cfb9ce238afde32b0148eb82cbe635620000000000000000000003fd;
    bytes32 public constant rethpoolbb = 0xda1cd1711743e57dd57102e9e61b75f3587703da0000000000000000000003fc;
    
    // Events
    event Deposit(uint256 tvl);
    event DepositPendle(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    struct PendleInitParams {
        address pendleToken;
        address pendleRouter;
        address pendlePTToken;
        address balancerVault;
    }

    address public pendleToken;
    address public pendleRouter;
    address public pendlePTToken;

    IVault public balancerVault;


    /**
    * @notice Initialize the contract with initial values.
    * @param _vaultAddress The address of the vault.
    * @param _assetAddress The address of the asset.
    * @param stratParams Parameters related to strategy fees.
    * @param pendleInitParams Parameters related to pendle params.
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        PendleInitParams calldata pendleInitParams
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        require(pendleInitParams.pendleToken != address(0), "Invalid pendleToken address");
        require(pendleInitParams.balancerVault != address(0), "Invalid balancerVault address");
        require(pendleInitParams.pendleRouter != address(0), "Invalid pendleRouter address");
        require(pendleInitParams.pendlePTToken != address(0), "Invalid pendlePTToken address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        pendleToken = pendleInitParams.pendleToken;
        balancerVault = IVault(pendleInitParams.balancerVault);
        pendleRouter = pendleInitParams.pendleRouter;
        pendlePTToken = pendleInitParams.pendlePTToken;
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
    * @notice Performs the harvest operation, claiming rewards pendle and swapping them to lp pendle token.
    */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IPendleMarket(this.asset()).redeemRewards(address(this));
        uint256 balance = IERC20(pendleToken).balanceOf(address(this));
        if (balance > 0) {
            chargeFees(callFeeRecipient);
            uint256 harvestAmount = IERC20(pendleToken).balanceOf(address(this));
            
            swapUniswap(pendleToken, weth, harvestAmount, 0);
            swapBalancer(weth, IERC20(weth).balanceOf(address(this)), 0);
            uint256 balanceRETH = IERC20(reth).balanceOf(address(this));
            _deposit(balanceRETH);
            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, harvestAmount);
        }
    }
    
   function _deposit(uint256 amount) internal {
        IPendleRouter.SwapData memory swapData = IPendleRouter.SwapData({
            swapType: IPendleRouter.SwapType.NONE,
            extRouter: address(0),
            extCalldata: '0x',
            needScale: false
        });
        IPendleRouter.TokenInput memory tokenInput = IPendleRouter.TokenInput({
            tokenIn: reth,
            netTokenIn: amount,
            tokenMintSy: reth,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: swapData
        });
        IPendleRouter.ApproxParams memory approx = IPendleRouter.ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0, // pass 0 in to skip this variable
            maxIteration: 256, // every iteration, the diff between guessMin and guessMax will be divided by 2
            eps: 1e15
        });
        
        (uint256 netOut, uint256 netSyFee) = IPendleRouter(pendleRouter).swapExactTokenForPt(address(this), this.asset(), 0, approx, tokenInput);
        
        IPendleRouter(pendleRouter).addLiquiditySinglePt(address(this), this.asset(), netOut, 0, approx);
        emit DepositPendle(amount);
   }

 

    /**
    * @notice Charges the performance fees after the harvest operation.
    */
    function chargeFees(address callFeeRecipient) internal {
        uint256 feeAmount = IERC20(pendleToken).balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);

        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        IERC20(pendleToken).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        IERC20(pendleToken).safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        IERC20(pendleToken).safeTransfer(strategist, strategistFeeAmount);

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
    * @notice Gives allowances to the pendle router.
    */
    function _giveAllowances() internal {
        IERC20(reth).safeApprove(pendleRouter, type(uint256).max);
        IERC20(pendlePTToken).safeApprove(pendleRouter, type(uint256).max);
    }

    /**
    * @notice Removes allowances from the pendle router.
    */
    function _removeAllowances() internal {
        IERC20(reth).safeApprove(pendleRouter, 0);
        IERC20(pendlePTToken).safeApprove(pendleRouter, 0);
    }

    /**
    * @notice Authorizes an upgrade of the strategy's implementation.
    * @param newImplementation The address of the new implementation.
    */
    function _authorizeUpgrade(address newImplementation) internal override {
        require(address(_vault) == msg.sender, 'Not vault!');
    }

    function swapBalancer(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal {
        // Construct the params for the swap
        IERC20(tokenIn).approve(address(balancerVault), amountIn);
        
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        uint256 deadline = block.timestamp; 
        IVault.BatchSwapStep memory step1 = IVault.BatchSwapStep({
            poolId: rethpoolbb,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: amountIn,
            userData: '0x'
        });
        IVault.BatchSwapStep memory step2 = IVault.BatchSwapStep({
            poolId: rethpool,
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: minAmountOut,
            userData: '0x'
        });
        IVault.BatchSwapStep[] memory steps = new IVault.BatchSwapStep[](2);
        steps[0] = step1;
        steps[1] = step2;
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(weth);
        assets[1] = IAsset(bbweth);
        assets[2] = IAsset(reth);
        // Perform the swap
        int256[] memory limits =  new int256[](3);
        limits[0] = int256(amountIn);
        limits[1] = 0;
        limits[2] = 0;
       
        balancerVault.batchSwap(IVault.SwapKind.GIVEN_IN, steps, assets, funds, limits, deadline);
    }

    function swapUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 amountOutMinimum
    ) internal returns (uint256) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);

        uint24 poolFee = 3000;

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
}
