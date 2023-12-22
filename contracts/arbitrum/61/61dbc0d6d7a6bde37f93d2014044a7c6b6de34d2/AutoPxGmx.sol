// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ReentrancyGuard} from "./lib_ReentrancyGuard.sol";
import {Owned} from "./Owned.sol";
import {PirexERC4626} from "./PirexERC4626.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {ERC20} from "./ERC20.sol";
import {PirexGmx} from "./PirexGmx.sol";
import {PirexRewards} from "./PirexRewards.sol";
import {IV3SwapRouter} from "./IV3SwapRouter.sol";

contract AutoPxGmx is ReentrancyGuard, Owned, PirexERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IV3SwapRouter public constant SWAP_ROUTER =
        IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint256 public constant MAX_WITHDRAWAL_PENALTY = 500;
    uint256 public constant MAX_PLATFORM_FEE = 2_000;
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_COMPOUND_INCENTIVE = 5_000;

    // Address of the rewards module (ie. PirexRewards instance)
    address public immutable rewardsModule;

    ERC20 public immutable gmxBaseReward;
    ERC20 public immutable gmx;

    uint256 public withdrawalPenalty = 300;
    uint256 public platformFee = 1_000;
    uint256 public compoundIncentive = 1_000;
    address public platform;

    // Uniswap pool fee
    uint24 public poolFee = 3_000;

    // Receives and distributes platform fees
    address public immutable pirexFees;

    // Maintain the amount of total assets after each vault operation that affects it
    // In this case, pxGMX was added as a result of the compound operation
    // This allows us to maintain a delayed account of pxGMX, preventing external operators
    // from claiming the rewards independently from the vault
    uint256 public vaultTotalAssets;

    event PoolFeeUpdated(uint24 _poolFee);
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 incentive);
    event PlatformUpdated(address _platform);
    event Compounded(
        address indexed caller,
        uint24 fee,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 gmxBaseRewardAmountIn,
        uint256 gmxAmountOut,
        uint256 pxGmxMintAmount,
        uint256 totalFee,
        uint256 incentive
    );

    error ZeroAmount();
    error ZeroAddress();
    error InvalidAssetParam();
    error ExceedsMax();
    error AlreadySet();
    error InvalidParam();
    error ZeroShares();

    /**
        @param  _gmxBaseReward  address  GMX reward token contract address
        @param  _gmx            address  GMX token contract address
        @param  _asset          address  Asset address (e.g. pxGMX)
        @param  _name           string   Asset name (e.g. Autocompounding pxGMX)
        @param  _symbol         string   Asset symbol (e.g. apxGMX)
        @param  _platform       address  Platform address (e.g. PirexGmx)
        @param  _rewardsModule  address  Rewards module address
        @param  _pirexFees      address  PirexFees contract address
     */
    constructor(
        address _gmxBaseReward,
        address _gmx,
        address _asset,
        string memory _name,
        string memory _symbol,
        address _platform,
        address _rewardsModule,
        address _pirexFees
    ) Owned(msg.sender) PirexERC4626(ERC20(_asset), _name, _symbol) {
        if (_gmxBaseReward == address(0)) revert ZeroAddress();
        if (_gmx == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (bytes(_name).length == 0) revert InvalidAssetParam();
        if (bytes(_symbol).length == 0) revert InvalidAssetParam();
        if (_platform == address(0)) revert ZeroAddress();
        if (_rewardsModule == address(0)) revert ZeroAddress();
        if (_pirexFees == address(0)) revert ZeroAddress();

        gmxBaseReward = ERC20(_gmxBaseReward);
        gmx = ERC20(_gmx);
        platform = _platform;
        rewardsModule = _rewardsModule;
        pirexFees = _pirexFees;

        // Approve the Uniswap V3 router to manage our base reward (inbound swap token)
        gmxBaseReward.safeApprove(address(SWAP_ROUTER), type(uint256).max);
        gmx.safeApprove(_platform, type(uint256).max);
    }

    /**
        @notice Constructs ExactInputSingleParams with constant field values pre-defined (e.g. recipient)
        @param  amountIn           uint256                               Input token amount
        @param  amountOutMinimum   uint256                               Minimum output token amount
        @param  sqrtPriceLimitX96  uint160                               The Q64.96 sqrt price limit
        @return                    IV3SwapRouter.ExactInputSingleParams
     */
    function _getExactInputSingleParams(
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) private view returns (IV3SwapRouter.ExactInputSingleParams memory) {
        return
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(gmxBaseReward),
                tokenOut: address(gmx),
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });
    }

    /**
        @notice Set the Uniswap pool fee
        @param  _poolFee  uint24  Uniswap pool fee
     */
    function setPoolFee(uint24 _poolFee) external onlyOwner {
        if (_poolFee == 0) revert ZeroAmount();

        poolFee = _poolFee;

        emit PoolFeeUpdated(_poolFee);
    }

    /**
        @notice Set the withdrawal penalty
        @param  penalty  uint256  Withdrawal penalty
     */
    function setWithdrawalPenalty(uint256 penalty) external onlyOwner {
        if (penalty > MAX_WITHDRAWAL_PENALTY) revert ExceedsMax();

        withdrawalPenalty = penalty;

        emit WithdrawalPenaltyUpdated(penalty);
    }

    /**
        @notice Set the platform fee
        @param  fee  uint256  Platform fee
     */
    function setPlatformFee(uint256 fee) external onlyOwner {
        if (fee > MAX_PLATFORM_FEE) revert ExceedsMax();

        platformFee = fee;

        emit PlatformFeeUpdated(fee);
    }

    /**
        @notice Set the compound incentive
        @param  incentive  uint256  Compound incentive
     */
    function setCompoundIncentive(uint256 incentive) external onlyOwner {
        if (incentive > MAX_COMPOUND_INCENTIVE) revert ExceedsMax();

        compoundIncentive = incentive;

        emit CompoundIncentiveUpdated(incentive);
    }

    /**
        @notice Set the platform
        @param  _platform  address  Platform
     */
    function setPlatform(address _platform) external onlyOwner {
        if (_platform == address(0)) revert ZeroAddress();

        // Update GMX transfer allowance for the old and new platforms
        gmx.safeApprove(platform, 0);
        gmx.safeApprove(_platform, type(uint256).max);

        platform = _platform;

        emit PlatformUpdated(_platform);
    }

    /**
        @notice Get the pxGMX custodied by the AutoPxGmx contract
        @return uint256  Amount of pxGMX custodied by the autocompounder
     */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
        @notice Preview the amount of assets a user would receive from redeeming shares
        @param  shares  uint256  Shares
        @return uint256  Assets
     */
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        // Calculate assets based on a user's % ownership of vault shares
        uint256 assets = convertToAssets(shares);

        uint256 _totalSupply = totalSupply;

        // Calculate a penalty - zero if user is the last to withdraw
        uint256 penalty = (_totalSupply == 0 || _totalSupply - shares == 0)
            ? 0
            : assets.mulDivDown(withdrawalPenalty, FEE_DENOMINATOR);

        // Redeemable amount is the post-penalty amount
        return assets - penalty;
    }

    /**
        @notice Preview the amount of shares a user would need to redeem the specified asset amount
        @notice This modified version takes into consideration the withdrawal fee
        @param  assets   uint256  Assets
        @return          uint256  Shares
     */
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        // Calculate shares based on the specified assets' proportion of the pool
        uint256 shares = convertToShares(assets);

        // Save 1 SLOAD
        uint256 _totalSupply = totalSupply;

        // Factor in additional shares to fulfill withdrawal if user is not the last to withdraw
        return
            (_totalSupply == 0 || _totalSupply - shares == 0)
                ? shares
                : shares.mulDivUp(
                    FEE_DENOMINATOR,
                    FEE_DENOMINATOR - withdrawalPenalty
                );
    }

    /**
        @notice Return the maximum amount of assets the specified account can withdraw
        @param  account  address  Account address
        @return          uint256  Assets
     */
    function maxWithdraw(address account)
        public
        view
        override
        returns (uint256)
    {
        return previewRedeem(balanceOf[account]);
    }

    /**
        @notice Compound pxGMX rewards before depositing
     */
    function beforeDeposit(
        address,
        uint256,
        uint256
    ) internal override {
        compound(1, 0, true);
    }

    function afterWithdraw(
        address,
        uint256,
        uint256
    ) internal override {
        vaultTotalAssets = totalAssets();
    }

    function afterDeposit(
        address,
        uint256,
        uint256
    ) internal override {
        vaultTotalAssets = totalAssets();
    }

    /**
        @notice Compound pxGMX rewards
        @param  amountOutMinimum       uint256  Outbound token swap amount
        @param  sqrtPriceLimitX96      uint160  Swap price impact limit (optional)
        @param  optOutIncentive        bool     Whether to opt out of the incentive
        @return gmxBaseRewardAmountIn  uint256  GMX base reward inbound swap amount
        @return gmxAmountOut           uint256  GMX outbound swap amount
        @return pxGmxMintAmount        uint256  pxGMX minted when depositing GMX
        @return totalFee               uint256  Total platform fee
        @return incentive              uint256  Compound incentive
     */
    function compound(
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        bool optOutIncentive
    )
        public
        returns (
            uint256 gmxBaseRewardAmountIn,
            uint256 gmxAmountOut,
            uint256 pxGmxMintAmount,
            uint256 totalFee,
            uint256 incentive
        )
    {
        if (amountOutMinimum == 0) revert InvalidParam();

        uint256 assetsBeforeClaim = vaultTotalAssets != 0
            ? vaultTotalAssets
            : totalAssets();

        // Make sure reward acrruals are up-to-date
        PirexRewards(rewardsModule).accrueAndClaim(address(this));

        // Swap entire reward balance for GMX
        gmxBaseRewardAmountIn = gmxBaseReward.balanceOf(address(this));

        if (gmxBaseRewardAmountIn != 0) {
            gmxAmountOut = SWAP_ROUTER.exactInputSingle(
                _getExactInputSingleParams(
                    gmxBaseRewardAmountIn,
                    amountOutMinimum,
                    sqrtPriceLimitX96
                )
            );

            // Deposit entire GMX balance for pxGMX, increasing the asset/share amount
            // pxGmxMintAmount is the pxGMX received by the vault *after* Pirex-GMX fees
            (pxGmxMintAmount, ) = PirexGmx(platform).depositGmx(
                gmx.balanceOf(address(this)),
                address(this)
            );
        }

        // Only distribute fees if the amount of vault assets increased
        uint256 newAssets = totalAssets() - assetsBeforeClaim;

        if (newAssets != 0) {
            totalFee = newAssets.mulDivDown(platformFee, FEE_DENOMINATOR);
            incentive = optOutIncentive
                ? 0
                : totalFee.mulDivDown(compoundIncentive, FEE_DENOMINATOR);

            if (incentive != 0) asset.safeTransfer(msg.sender, incentive);

            asset.safeTransfer(pirexFees, totalFee - incentive);
        }

        vaultTotalAssets = totalAssets();

        emit Compounded(
            msg.sender,
            poolFee,
            amountOutMinimum,
            sqrtPriceLimitX96,
            gmxBaseRewardAmountIn,
            gmxAmountOut,
            pxGmxMintAmount,
            totalFee,
            incentive
        );
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address account
    ) public override returns (uint256 shares) {
        // Compound rewards and ensure they are properly accounted for prior to withdrawal calculation
        compound(1, 0, true);

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != account) {
            uint256 allowed = allowance[account][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[account][msg.sender] = allowed - shares;
        }

        _burn(account, shares);

        emit Withdraw(msg.sender, receiver, account, assets, shares);

        asset.safeTransfer(receiver, assets);

        afterWithdraw(account, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address account
    ) public override returns (uint256 assets) {
        // Compound rewards and ensure they are properly accounted for prior to redemption calculation
        compound(1, 0, true);

        if (msg.sender != account) {
            uint256 allowed = allowance[account][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[account][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(account, shares);

        emit Withdraw(msg.sender, receiver, account, assets, shares);

        asset.safeTransfer(receiver, assets);

        afterWithdraw(account, assets, shares);
    }

    /**
        @notice Deposit GMX for apxGMX
        @param  amount    uint256  GMX amount
        @param  receiver  address  apxGMX receiver
        @return shares    uint256  Vault shares (i.e. apxGMX)
     */
    function depositGmx(uint256 amount, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Handle compounding of rewards before deposit (arguments are not used by `beforeDeposit` hook)
        if (totalAssets() != 0) beforeDeposit(address(0), 0, 0);

        // Intake sender GMX
        gmx.safeTransferFrom(msg.sender, address(this), amount);

        // Convert sender GMX into pxGMX and get the post-fee amount (i.e. assets)
        (uint256 postFeeAssets, ) = PirexGmx(platform).depositGmx(
            amount,
            address(this)
        );

        // NOTE: Modified `convertToShares` logic to consider assets already being in the vault
        // and handle it by deducting the recently-deposited assets from the total
        uint256 supply = totalSupply;

        if (
            (shares = supply == 0
                ? postFeeAssets
                : postFeeAssets.mulDivDown(
                    supply,
                    totalAssets() - postFeeAssets
                )) == 0
        ) revert ZeroShares();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, postFeeAssets, shares);

        afterDeposit(receiver, postFeeAssets, shares);
    }
}

