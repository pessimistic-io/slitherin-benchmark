// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IGMXRouter } from "./IGMXRouter.sol";
import { IGLPManager } from "./IGLPManager.sol";
import { IStrategy } from "./IStrategy.sol";
import { RewardRouter, OrderBook } from "./IMux.sol";
import { IWETH } from "./IWETH.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { OracleLibrary } from "./OracleLibrary.sol";
import { IERC20Extended } from "./IERC20Extended.sol";

/**
 * @title MuxStrategy
 * @notice This contract is a strategy that interacts with the MUX protocol. The MUX Protocol Suite is a complex of protocols that offer optimized trading cost, deep liquidity, a wide range of leverage options, and diverse market options for traders. This strategy automates certain actions such as minting GMX's GLP tokens, claiming fees, and charging performance fees.
 * @dev The strategy uses the MUX Leveraged Trading Protocol and MUX Leveraged Trading Aggregator. The Leveraged Trading Protocol offers zero price impact trading, up to 100x leverage, no counterparty risks for traders, and an optimized on-chain trading experience. The Leveraged Trading Aggregator automatically selects the most suitable liquidity route and minimizes the composite cost for traders while meeting the needs of opening positions. It can also supply additional margin for traders to raise the leverage up to 100x on aggregated underlying protocols.
 */
contract MuxStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant smlp = 0x0a9bbf8299FEd2441009a7Bb44874EE453de8e5D;
    address public constant fmlp = 0x290450cDea757c68E4Fe6032ff3886D204292914;
    address public constant wethUsdcPool = 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;
    
    // Events
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    address public rewardRouter;
    address public orderBook;

    ISwapRouter public uniswapV3Router;

     /**
    * @notice Initialize the contract with initial values.
    * @dev Initializes the contract by setting the vault and asset addresses, and sets up the necessary parameters for the strategy.
    * @param _vaultAddress The address of the vault. Must not be the zero address.
    * @param _assetAddress The address of the asset. Must not be the zero address.
    * @param stratParams The parameters for the strategy's fees.
    * @param _rewardRouter The address of the RewardRouter contract.
    * @param _orderBook The address of the OrderBook contract.
    */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        address _rewardRouter,
        address _orderBook
    ) public initializer {
        require(_vaultAddress != address(0), "Invalid vault address");
        require(_assetAddress != address(0), "Invalid asset address");
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        rewardRouter = _rewardRouter;
        orderBook = _orderBook;
        uniswapV3Router = ISwapRouter(swapRouter);
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
        return _asset.balanceOf(address(this)) + balanceOfPool(); 
    }

    function balanceOfPool() internal view returns (uint256) {
        return IERC20(smlp).balanceOf(address(this));
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
        uint256 muxLPBalanceAfterFee = _asset.balanceOf(address(this));
        RewardRouter(rewardRouter).stakeMlp(muxLPBalanceAfterFee);
        emit Deposit(muxLPBalanceAfterFee);
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
    function harvest() external onlyKeeper onlyKeeper nonReentrant {
        _harvest(tx.origin);
    }

    /**
    * @notice Performs the harvest operation, claiming rewards and swapping them to the input silo token.
    */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        RewardRouter(rewardRouter).claimFromMlpUnwrap();
        uint256 bal = address(this).balance;
        if (bal > 0) {
            convertEthToUsdc(bal);
            uint256 prevBalance = IERC20(usdc).balanceOf(address(this));
            chargeFees(callFeeRecipient);
            uint256 afterBalance = IERC20(usdc).balanceOf(address(this));
            OrderBook(orderBook).placeLiquidityOrder(0, uint96(afterBalance), true);
            lastHarvest = block.timestamp;
            uint256 muxLPBalance = _asset.balanceOf(address(this));
            if (muxLPBalance > 0) {
                RewardRouter(rewardRouter).stakeMlp(muxLPBalance);
            }
            emit StrategyHarvested(msg.sender, prevBalance);
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
    * @notice Withdraws the specified amount of tokens and sends them to the vault.
    * @param amount The amount of tokens to be withdrawn.
    */
    function withdraw(uint256 amount) external nonReentrant {
        require(msg.sender == address(_vault), "!vault");
        uint256 totalBalance = this.balanceOf();
        require(amount <= totalBalance, "Insufficient total balance");
        if (amount > _asset.balanceOf(address(this))) {
            RewardRouter(rewardRouter).unstakeMlp(amount);
        }
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
        RewardRouter(rewardRouter).unstakeMlp(IERC20(smlp).balanceOf(address(this)));
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
        IERC20(usdc).safeApprove(orderBook, type(uint256).max);
        _asset.safeApprove(rewardRouter, type(uint256).max);
        _asset.safeApprove(fmlp, type(uint256).max);
        IERC20(weth).safeApprove(address(swapRouter), type(uint256).max);
    }

    /**
    * @notice Removes allowances from the silo pool and swap router for the silo asset and silo token.
    */
    function _removeAllowances() internal {
        IERC20(usdc).safeApprove(orderBook, 0);
        _asset.safeApprove(rewardRouter, 0);
        _asset.safeApprove(fmlp, 0);
        IERC20(weth).safeApprove(address(swapRouter), 0);
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

    /**
    * @notice Converts a specified amount of Ether into USDC.
    * @dev This function uses Uniswap or another DEX to convert Ether into USDC. It reverts if the amount of USDC received is less than `amountOutMinimum`.
    * @param amountIn The amount of Ether (in wei) to convert. This amount of Ether must be available on the contract.
    * @return The actual amount of USDC received from the conversion.
    */
    function convertEthToUsdc(uint256 amountIn) internal returns (uint256) {
        // Wrap ETH
        IWETH(weth).deposit{value: amountIn}();
        // Define the path to swap along
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = usdc;

        uint256 amountOutExpected = getPrice(weth, usdc, wethUsdcPool);
         // Adjust the expected output by the input amount.
        // This is a simplified example and may not give the exact expected output, 
        // particularly for large trades that could significantly move the price.
        amountOutExpected = (amountOutExpected * amountIn) / (10**IERC20Extended(weth).decimals());
        
        // Set the minimum accepted output amount to be example: 99% of the expected amount, allowing for 1% slippage
        uint256 amountOutMinimum = amountOutExpected.mul((slippage).div(SLIPPAGE_SCALE));

        // Set up parameters for the swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: path[0],
            tokenOut: path[1],
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // Execute the swap
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

    receive() external payable {}
}
