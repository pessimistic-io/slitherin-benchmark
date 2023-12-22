// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IStrategy } from "./IStrategy.sol";
import { IStableJoeStaking, ILBRouter, ILBQuoter } from "./ITraderJoe.sol";
import { ICamelot } from "./ICamelot.sol";
import { StratManager } from "./StratManager.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { IChainlinkAggregatorV3 } from "./IChainlinkAggregatorV3.sol";

/**
 * @title TraderJoeStrategy
 * @dev This contract is the strategy for farming tokens on TraderJoe's platform.
 * It inherits from IStrategy, StratManager, ReentrancyGuard, and UUPSUpgradeable.
 */
contract TraderJoeStrategy is IStrategy, StratManager, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 private _vault;
    IERC20 private _asset;

    address public constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public joeStakingAddress;
    address public joeQuoter;


    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    // Events
    event Deposit(address indexed pool, uint256 indexed amount);
    event Withdraw(address indexed pool, uint256 indexed amount);
    event StrategyHarvested(address indexed harvester, uint256 wantHarvested);
    event ChargedFees(uint256 callFees, uint256 factorFees, uint256 strategistFees);
    event DepositFeeCharge(uint256 amount);

    /**
     * @dev Constructor function.
     * @param _vaultAddress The address of the vault contract.
     * @param _assetAddress The address of the asset (token) to be farmed.
     * @param stratParams StratFeeManagerParams struct with the required StratManager initialization parameters.
     * @param _joeStakingAddress Address of the staking contract on TraderJoe.
     * @param _joeQuoter Address of the Joe Quoter contract.
     * The function requires that none of the input addresses are the zero address.
     */
    function initialize(
        address _vaultAddress,
        address _assetAddress,
        StratFeeManagerParams calldata stratParams,
        address _joeStakingAddress,
        address _joeQuoter
    ) public initializer {
        require(_vaultAddress != address(0), 'Invalid vault address');
        require(_assetAddress != address(0), 'Invalid asset address');
        require(_joeStakingAddress != address(0), 'Invalid joeStakingAddress address');
        __StratFeeManager_init(stratParams);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _vault = IERC20(_vaultAddress);
        _asset = IERC20(_assetAddress);
        joeStakingAddress = _joeStakingAddress;
        joeQuoter = _joeQuoter;
        _giveAllowances();
    }

    function userInfo() internal view returns (uint256, uint256) {
        return IStableJoeStaking(joeStakingAddress).getUserInfo(address(this), usdc);
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
        (uint256 balance, ) = userInfo();
        return _asset.balanceOf(address(this)) + balance;
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
        _deposit(_asset.balanceOf(address(this)));
    }

    function depositFeeCharge() internal {
        uint256 amount = afterDepositBalance - beforeDepositBalance;
        uint256 depositFeeAmount = amount.mul(depositFee).div(FEE_SCALE);
        _asset.safeTransfer(factorFeeRecipient, depositFeeAmount);
        emit DepositFeeCharge(depositFeeAmount);
    }

    /**
     * @notice Deposits the specified amount of tokens into the joe pool.
     * @param amount The amount of tokens to be deposited.
     */
    function _deposit(uint256 amount) internal whenNotPaused {
        IStableJoeStaking(joeStakingAddress).deposit(amount);
        emit Deposit(joeStakingAddress, amount);
    }

    /**
     * @notice Allows an external user to perform the harvest operation.
     */
    function harvest() external nonReentrant {
        _harvest(tx.origin);
    }

    /**
     * @notice Performs the harvest operation, claiming rewards and swapping them to the input radiant token.
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IStableJoeStaking(joeStakingAddress).deposit(0);
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        if (usdcBalance > 0) {
            // swap to usdc
            chargeFees(callFeeRecipient);
            _swap(usdc, this.asset(), IERC20(usdc).balanceOf(address(this)));
            uint256 balanceDeposit = this.balanceOf();
            if (balanceDeposit > 0) {
                _deposit(balanceDeposit);
            }
            lastHarvest = block.timestamp;
            emit StrategyHarvested(msg.sender, usdcBalance);
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
     * @notice Withdraws the specified amount of tokens from the lending pool.
     * @param amount The amount of tokens to be withdrawn.
     */
    function _withdraw(uint256 amount) internal {
        IStableJoeStaking(joeStakingAddress).withdraw(amount);
        emit Withdraw(joeStakingAddress, amount);
    }

    /**
     * @notice Withdraws the specified amount of tokens and sends them to the vault.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(msg.sender == address(_vault), '!vault');
        uint256 totalBalance = this.balanceOf();
        require(amount <= totalBalance, 'Insufficient total balance');
        _withdraw(amount);
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
        (uint256 balancePool, ) = userInfo();
        _withdraw(balancePool);
        _asset.safeTransfer(this.vault(), this.balanceOf());
    }

    /**
     * @notice Emergency function to withdraw all assets and pause the strategy.
     */
    function panic() external onlyManager {
        (uint256 balancePool, ) = userInfo();
        _withdraw(balancePool);
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
        _asset.safeApprove(joeStakingAddress, type(uint256).max);
        IERC20(usdc).safeApprove(swapRouter, type(uint256).max);
    }

    /**
     * @notice Removes allowances from the lending pool and swap router for the radiant asset and radiant token.
     */
    function _removeAllowances() internal {
        _asset.safeApprove(joeStakingAddress, 0);
        IERC20(usdc).safeApprove(swapRouter, 0);
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

    // get price from Chainlink
    function _getPrice(address baseFeed) internal view returns (uint256) {
        //joe - usd
        (, int256 basePrice, , , ) = IChainlinkAggregatorV3(baseFeed).latestRoundData();

        //usdc - usd
        (, int256 quotePrice, , , ) = IChainlinkAggregatorV3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3)
            .latestRoundData();

        uint256 price = (uint256(basePrice) * (10 ** 6)) / uint256(quotePrice);
        require(price > 0, "Price can't zero");

        return price;
    }

    // joe price USDC
    function joePriceUSD() internal view returns (uint256) {
        return _getPrice(0x04180965a782E487d0632013ABa488A472243542);
    }
    //swap usdc - weth - joe
    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal returns (uint256) {
        address[] memory tokenPath = new address[](3);
        tokenPath[0] = tokenIn;
        tokenPath[1] = weth;
        tokenPath[2] = tokenOut;

        ILBQuoter.Quote memory quote = ILBQuoter(joeQuoter).findBestPathFromAmountIn(tokenPath, uint128(amount));
        
        uint256 amountOutExpected = amount / joePriceUSD();
        // Set the minimum accepted output amount to be 99% of the expected amount, allowing for 1% slippage
        uint256 amountOutMinimum = amountOutExpected.mul(slippage.div(SLIPPAGE_SCALE));
        ILBRouter.Path memory params = ILBRouter.Path({
            pairBinSteps: quote.binSteps,
            versions: quote.versions,
            tokenPath: tokenPath
        });
        return ILBRouter(swapRouter).swapExactTokensForTokens(amount, amountOutMinimum, params, address(this), block.timestamp);
    }
}

