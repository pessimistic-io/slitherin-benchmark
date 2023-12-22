// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { ITenderTroller, ITenderComp, ITenderInstantVester } from "./ITender.sol";
import { ICamelot } from "./ICamelot.sol";
import { IWETH } from "./IWETH.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";

/**
 * @title TenderStrategy
 */
contract TenderStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    // Third party contracts
    address public tenderAssetDeposit;
    address public tenderToken;
    address public tenderComp;
    address public tenderVester;
    address public tenderUniTroller;
    address public tenderVestedToken;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    // Events
    event Deposit(uint256 indexed tvl);
    event Withdraw(uint256 indexed tvl);
    event DepositTender(uint256 indexed amount);
    event WithdrawTender(uint256 indexed amount);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    // TenderFinance initialization parameters struct
    struct TenderInitParams {
        address tenderAssetDeposit;
        address tenderToken;
        address tenderVestedToken;
        address tenderComp;
        address tenderVester;
        address tenderUniTroller;
    }

    /**
     * @notice Initializes the TenderStrategy contract with the provided parameters.
     * @param _vaultAddress The address of the vault contract.
     * @param _assetAddress The address of the asset (token) to be farmed.
     * @param stratParams StratFeeManagerParams struct with the required StratManager initialization parameters.
     * @param initParams TenderInitParams struct with the required Tender initialization parameters.
     */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        TenderInitParams calldata initParams
    ) public initializer {
        require(_vaultAddress != address(0), 'Invalid vault address');
        require(_assetAddress != address(0), 'Invalid asset address');
       
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        tenderAssetDeposit = initParams.tenderAssetDeposit;
        tenderToken = initParams.tenderToken;
        tenderComp = initParams.tenderComp;
        tenderVester = initParams.tenderVester;
        tenderVestedToken = initParams.tenderVestedToken;
        tenderUniTroller = initParams.tenderUniTroller;
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
     * @notice Returns the balance of the input tender token held by the contract.
     * @return The balance of the input tender token.
     */
    function balanceOfInputTenderDeposit() external view returns (uint256) {
        if (tenderAssetDeposit == address(0)) {
            return address(this).balance;
        }
        return IERC20(tenderAssetDeposit).balanceOf(address(this));
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
     * @notice Deposits the specified amount of tokens into the TenderFinance.
     * @param amount The amount of tokens to be deposited.
     */
    function _deposit(uint256 amount) internal whenNotPaused {
        if (tenderAssetDeposit == address(0)) {
            ITenderComp(tenderComp).mint();
        } else{
            ITenderComp(tenderComp).mint(amount);
        }
        emit DepositTender(amount);
    }

    /**
     * @notice Allows an external user to perform the harvest operation.
     */
    function harvest() external onlyKeeper nonReentrant {
        _harvest(tx.origin);
    }

    /**
     * @notice Performs the harvest operation, claiming rewards and swapping them to the input TenderFinance token.
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        
        ITenderTroller(tenderUniTroller).claimComp(address(this));
        
        uint256 tenderTokenBal = IERC20(tenderToken).balanceOf(address(this));

        ITenderInstantVester(tenderVester).instantVest(tenderTokenBal);
        uint256 tenderVestedTokenBal = IERC20(tenderVestedToken).balanceOf(address(this));
        if (tenderVestedTokenBal > 0) {
            // swap to tokendeposit
            address tokenDeposit = tenderAssetDeposit == address(0) ? weth : tenderAssetDeposit;
            _swap(tenderVestedToken, tokenDeposit, tenderVestedTokenBal, 0);
            uint256 harvestedAmount = IERC20(tokenDeposit).balanceOf(address(this));
            chargeFees(callFeeRecipient);
            uint256 balanceDeposit = IERC20(tokenDeposit).balanceOf(address(this));
            if (balanceDeposit > 0) {
                if (tenderAssetDeposit == address(0)) {
                    IWETH(tokenDeposit).withdraw(balanceDeposit);
                }
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
        address tokenDeposit = tenderAssetDeposit == address(0) ? weth : tenderAssetDeposit;
        uint256 feeAmount = IERC20(tokenDeposit).balanceOf(address(this)).mul(performanceFee).div(FEE_SCALE);
        uint256 callFeeAmount = feeAmount.mul(callFee).div(FEE_SCALE);
        IERC20(tokenDeposit).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 factorFeeAmount = feeAmount.mul(factorFee).div(FEE_SCALE);
        IERC20(tokenDeposit).safeTransfer(factorFeeRecipient, factorFeeAmount);

        uint256 strategistFeeAmount = feeAmount.mul(strategistFee).div(FEE_SCALE);
        IERC20(tokenDeposit).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, factorFeeAmount, strategistFeeAmount);
    }

    /**
     * @notice Withdraws the specified amount of tokens from the lending pool.
     * @param amount The amount of tokens to be withdrawn.
     */
    function _withdraw(uint256 amount) internal {
        ITenderComp(tenderComp).redeem(amount);
        emit WithdrawTender(amount);
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
        emit Withdraw(this.balanceOf());
    }

    /**
     * @notice Exits the strategy by withdrawing all the assets.
     */
    function exit() external nonReentrant {
        require(msg.sender == address(_vault), '!vault');
        _withdraw(this.balanceOf());
        address assetDeposit = tenderAssetDeposit;
        uint256 amount = this.balanceOfInputTenderDeposit();
        if (tenderAssetDeposit == address(0)) {
            IWETH(weth).deposit{value: address(this).balance}();
            assetDeposit = weth;
            amount = IERC20(weth).balanceOf(address(this));
        }
        IERC20(assetDeposit).safeTransfer(this.vault(), amount);
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
     * @notice Gives allowances 
     */
    function _giveAllowances() internal {
        address[] memory path = new address[](1);
        path[0] = this.asset();
        ITenderTroller(tenderUniTroller).enterMarkets(path);
        // If the deposit token is not Ether, approve it
        if (tenderAssetDeposit != address(0)) {
            IERC20(tenderAssetDeposit).safeApprove(tenderComp, type(uint256).max);
        }   
        IERC20(tenderToken).safeApprove(swapRouter, type(uint256).max);
    }

    /**
     * @notice Removes allowances
     */
    function _removeAllowances() internal {
        ITenderTroller(tenderUniTroller).exitMarket(this.asset());
        // If the deposit token is not Ether, disapprove it
        if (tenderAssetDeposit != address(0)) {
            IERC20(tenderAssetDeposit).safeApprove(tenderComp, 0);
        }
        IERC20(tenderToken).safeApprove(swapRouter, 0);
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

    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 amountOutMinimum
    ) internal returns (uint256) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);

        uint24 poolFee = 10000;

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

    receive() external payable {}
}
