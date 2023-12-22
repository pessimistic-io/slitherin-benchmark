// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./AggregatorV3Interface.sol";
import "./ILendingPool.sol";
import "./IGLPManager.sol";
import "./IGLPVault.sol";
import "./GLPLeverageStrategyStorage.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract GLPLeverageStrategy is Initializable, OwnableUpgradeable, UUPSUpgradeable, GLPLeverageStrategyStorage {
    using MathUpgradeable for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address wrappedGLP_,
        address sGLP_,
        address weth_,
        address swapRouter_,
        uint16 lendingPoolRewardShare_,
        uint256 minimumCollateralRatio_,
        uint256 targetCollateralRatio_
    ) public virtual initializer {
        __GLPLeverageStrategy_init(
            wrappedGLP_,
            sGLP_,
            weth_,
            swapRouter_,
            lendingPoolRewardShare_,
            minimumCollateralRatio_,
            targetCollateralRatio_
        );
    }

    function __GLPLeverageStrategy_init(
        address wrappedGLP_,
        address sGLP_,
        address weth_,
        address swapRouter_,
        uint16 lendingPoolRewardShare_,
        uint256 minimumCollateralRatio_,
        uint256 targetCollateralRatio_
    ) internal onlyInitializing {
        require(targetCollateralRatio_ > 1e18, "targetCollateralRatio must be higher than 1e18");
        require(
            minimumCollateralRatio_ < targetCollateralRatio_,
            "minimum collateral ratio must be below target collateral ratio"
        );
        require(lendingPoolRewardShare <= BASIS_POINT, "reward share over 100%");

        __Ownable_init();
        __UUPSUpgradeable_init();

        sGLP = IERC20MetadataUpgradeable(sGLP_);
        weth = IERC20MetadataUpgradeable(weth_);
        wrappedGLP = IWrappedGLP(wrappedGLP_);

        minimumCollateralRatio = minimumCollateralRatio_;
        targetCollateralRatio = targetCollateralRatio_;

        swapRouter = ISwapRouter(swapRouter_);
        lendingPoolRewardShare = lendingPoolRewardShare_;

        ethUSDOracle = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
        ethUSDOracleRefreshRate = 1 hours; // Default/Fallback ETH/USD refresh rate of 1hr

        glpEquity = 0;
        lastRewardClaimTime = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "unauthorized");
        _;
    }

    modifier onlyLendingPool() {
        require(msg.sender == address(lendingPool), "unauthorized");
        _;
    }

    modifier onlyVaultOrLendingPool() {
        require(msg.sender == address(lendingPool) || msg.sender == vault, "unauthorized");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper, "unauthorized");
        _;
    }

    // ADMIN METHODS

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setLeverageConfig(uint256 minimumCollateralRatio_, uint256 targetCollateralRatio_) public onlyOwner {
        require(targetCollateralRatio > 1e18, "targetCollateralRatio must be higher than 1e18");
        require(
            minimumCollateralRatio < targetCollateralRatio,
            "minimum collateral ratio must be below target collateral ratio"
        );
        minimumCollateralRatio = minimumCollateralRatio_;
        targetCollateralRatio = targetCollateralRatio_;
    }

    function setLendingPoolRewardShare(uint16 rewardShare) public onlyOwner {
        require(lendingPoolRewardShare != rewardShare, "reward share unchanged");
        require(lendingPoolRewardShare <= BASIS_POINT, "reward share over 100%");
        lendingPoolRewardShare = rewardShare;
    }

    function setContract(Contracts c, address cAddress) public onlyOwner {
        require(cAddress != address(0));

        if (c == Contracts.SwapRouter) {
            swapRouter = ISwapRouter(cAddress);
            return;
        }

        if (c == Contracts.GLPRewardRouterV2) {
            glpRewardRouterV2 = IRewardRouterV2(cAddress);
            return;
        }

        if (c == Contracts.LendingPool) {
            lendingPool = ILendingPool(cAddress);
            return;
        }

        if (c == Contracts.ETHUSDOracle) {
            ethUSDOracle = AggregatorV3Interface(cAddress);
            return;
        }

        if (c == Contracts.Vault) {
            vault = cAddress;
            return;
        }

        if (c == Contracts.Keeper) {
            keeper = cAddress;
            return;
        }
    }

    function setEthUSDOracleRefreshRate(uint256 rate) public onlyOwner {
        require(rate > 0, "eth/usd refresh rate must be greater than 0");

        ethUSDOracleRefreshRate = rate;
    }

    // PUBLIC METHODS

    function balanceOfEquity() public view returns (uint256) {
        return glpEquity;
    }

    function deposit(uint256 amount) public virtual onlyVault {
        _deposit(amount);
    }

    function withdrawTo(address account, uint256 amount) public virtual onlyVault {
        _withdrawTo(account, amount);
    }

    function rebalance() public virtual onlyVaultOrLendingPool {
        _rebalance(0);
    }

    function claimRewards() public virtual onlyVaultOrLendingPool {
        _claimRewards();
    }

    // Returns amount minus cost of the rebalance induced by the withdraw
    function prepareWithdrawGLP(uint256 amount) public onlyVault returns (uint256) {
        return _prepareWithdrawGLP(amount);
    }

    // Returns amount minus cost of the rebalance induced by the withdraw
    function prepareWithdrawLendingAsset(uint256 amount) public onlyLendingPool returns (uint256) {
        return _prepareWithdrawLendingAsset(amount);
    }

    function claimAndRebalance() public onlyKeeper {
        _claimRewards();
        _rebalance(0);
    }

    function previewWithdrawGLP(uint256 amount) public view returns (uint256) {
        uint256 inducedFees = _calculateInducedFeesGLP(amount);

        if (inducedFees > 0 && amount > 0) {
            return amount - inducedFees;
        }

        return amount;
    }

    // Returns amount of USDC recovered from a rebalance
    function previewWithdrawLentAsset(uint256 amount) public view returns (uint256) {
        uint256 inducedFees = _calculateInducedFeesLendingAsset(amount);

        if (inducedFees > 0 && amount > 0) {
            return amount - inducedFees;
        }

        return amount;
    }

    // INTERNAL METHODS

    function _claimRewards() internal {
        uint256 now_ = block.timestamp;
        if (lastRewardClaimTime == now_) {
            return;
        }
        lastRewardClaimTime = now_;

        wrappedGLP.claimRewards();

        uint256 balanceWETH = weth.balanceOf(address(this));
        if (balanceWETH == 0) {
            return;
        }

        uint256 lendingPoolRewardShare_ = lendingPoolRewardShare;
        if (lendingPoolRewardShare_ > 0) {
            uint256 amountForLendingPool = balanceWETH.mulDiv(lendingPoolRewardShare_, BASIS_POINT);
            uint256 usdcAmount = _swapWETHToUSDC(amountForLendingPool);
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(lendingPool.asset()), address(lendingPool), usdcAmount);
        }

        uint256 targetCollateralRatio_ = targetCollateralRatio;
        (uint256 collateralRatio, uint256 collateralValue, uint256 borrowValue) = _getCollateralState(0);

        balanceWETH = weth.balanceOf(address(this));

        if (collateralRatio >= targetCollateralRatio_) {
            uint256 collateralRatioIncrease = _collateralRatioAdjustmentUp(
                collateralValue,
                borrowValue,
                targetCollateralRatio_
            );

            uint256 wethToMint = _usdToWETH(collateralRatioIncrease);

            if (wethToMint > 0) {
                if (wethToMint > balanceWETH) {
                    wethToMint = balanceWETH;
                }

                _buyGLP(address(weth), wethToMint, true);
            }
            if (balanceWETH > wethToMint) {
                _repayWithWETH(balanceWETH - wethToMint);
            }
        } else if (collateralRatio < targetCollateralRatio_) {
            uint256 collateralRatioReduction = _collateralRatioAdjustmentDown(
                collateralValue,
                borrowValue,
                targetCollateralRatio_
            );

            uint256 wethToRepay = _usdToWETH(collateralRatioReduction);

            if (wethToRepay > 0) {
                if (wethToRepay > balanceWETH) {
                    wethToRepay = balanceWETH;
                }

                _repayWithWETH(wethToRepay);
            }

            if (balanceWETH > wethToRepay) {
                _buyGLP(address(weth), balanceWETH - wethToRepay, true);
            }
        }
    }

    // Returns cost incured in respective currency
    function _rebalance(uint256 withdrawGLPAmount) internal returns (uint256) {
        (uint256 collateralRatio, uint256 collateralValue, uint256 borrowValue) = _getCollateralState(
            withdrawGLPAmount
        );

        if (collateralRatio < minimumCollateralRatio) {
            return _leverDown(collateralValue, borrowValue);
        } else if (collateralRatio > targetCollateralRatio) {
            _leverUp(collateralValue, borrowValue);
        }

        return 0;
    }

    function _leverUp(uint256 collateralValue, uint256 borrowValue) internal {
        // Borrow USDC and mint GLP

        uint256 collateralRatioIncrease = _collateralRatioAdjustmentUp(
            collateralValue,
            borrowValue,
            targetCollateralRatio
        );

        uint256 amountUsdcToBorrow = _usdToUSDC(collateralRatioIncrease); // We should not account for mint fees, our leverage increases based on amount borrowed
        uint256 usdcAvailable = IERC20Upgradeable(lendingPool.asset()).balanceOf(address(lendingPool));

        if (amountUsdcToBorrow > usdcAvailable) {
            amountUsdcToBorrow = usdcAvailable;
        }

        if (amountUsdcToBorrow > 0) {
            lendingPool.borrow(amountUsdcToBorrow);
            _buyGLP(lendingPool.asset(), amountUsdcToBorrow, false);
        }
    }

    function _leverDown(uint256 collateralValue, uint256 borrowValue) internal returns (uint256) {
        uint256 targetCollateralRatio_ = targetCollateralRatio;
        uint256 collateralRatioReductionWithChange = _collateralRatioAdjustmentDown(
            collateralValue,
            borrowValue,
            targetCollateralRatio_
        );

        // Redeem GLP for USDC
        (uint256 amountGLPToRedeem, ) = _usdToGLPWithCost(collateralRatioReductionWithChange);

        if (amountGLPToRedeem == 0) {
            return 0;
        }

        lendingPool.removeCollateral(amountGLPToRedeem, address(this));
        require(wrappedGLP.withdrawTo(address(this), amountGLPToRedeem));

        uint256 usdcReceived = glpRewardRouterV2.unstakeAndRedeemGlp(
            lendingPool.asset(),
            amountGLPToRedeem,
            0,
            address(this)
        );

        // Use USDC to repay lending pool
        SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(lendingPool.asset()), address(lendingPool), usdcReceived);
        lendingPool.repay(usdcReceived, address(this));

        (, , borrowValue) = _getCollateralState(0);

        uint256 newEquity = lendingPool.userCollateralAmount(address(this)) - _usdToGLP(borrowValue);
        uint256 inducedFeesInGLP = glpEquity - newEquity;
        glpEquity -= inducedFeesInGLP;
        return inducedFeesInGLP;
    }

    function _calculateInducedFeesGLP(uint256 amount) internal view returns (uint256) {
        (uint256 collateralRatio, uint256 collateralValue, uint256 borrowValue) = _getCollateralState(amount);

        if (collateralRatio < minimumCollateralRatio) {
            uint256 collateralRatioReductionWithdraw = _collateralRatioAdjustmentDown(
                collateralValue,
                borrowValue,
                targetCollateralRatio
            );

            (, collateralValue, ) = _getCollateralState(0);

            uint256 collateralRatioReductionNoWithdraw = _collateralRatioAdjustmentDown(
                collateralValue,
                borrowValue,
                targetCollateralRatio
            );

            uint256 inducedWithdrawAmount = collateralRatioReductionWithdraw - collateralRatioReductionNoWithdraw;

            if (inducedWithdrawAmount == 0) {
                return 0;
            }

            (uint256 glpToRedeem, ) = _usdToGLPWithCost(inducedWithdrawAmount);

            uint256 newBorrow = _usdToGLP(borrowValue) - _usdToGLP(inducedWithdrawAmount);

            uint256 newEquity = lendingPool.userCollateralAmount(address(this)) - glpToRedeem - newBorrow;

            return glpEquity - newEquity;
        }

        return 0;
    }

    function _calculateInducedFeesLendingAsset(uint256 amount) internal view returns (uint256) {
        uint256 cost;
        uint256 amountGLPToRedeem;
        (amountGLPToRedeem, cost) = _usdcToGLPWithCost(amount);

        amountGLPToRedeem -= cost;

        uint256 maxRedeem = lendingPool.userCollateralAmount(address(this)) - glpEquity;
        if (amountGLPToRedeem > maxRedeem) {
            amountGLPToRedeem = maxRedeem;
        }

        if (amountGLPToRedeem == 0) {
            return 0;
        }

        uint256 usdcReceived = _glpToUSDCWithCost(amountGLPToRedeem);

        return amount - usdcReceived;
    }

    function _prepareWithdrawGLP(uint256 amount) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        (uint256 collateralRatio, uint256 collateralValue, uint256 borrowValue) = _getCollateralState(0);
        if (collateralRatio < minimumCollateralRatio) {
            return _leverDown(collateralValue, borrowValue);
        }

        return amount - _rebalance(amount);
    }

    function _prepareWithdrawLendingAsset(uint256 amount) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        (uint256 collateralRatio, uint256 collateralValue, uint256 borrowValue) = _getCollateralState(0);

        if (collateralRatio < minimumCollateralRatio) {
            _leverDown(collateralValue, borrowValue);
        }

        (uint256 amountGLPToRedeem, uint256 cost) = _usdcToGLPWithCost(amount);

        amountGLPToRedeem -= cost;

        uint256 maxRedeem = lendingPool.userCollateralAmount(address(this)) - glpEquity;
        if (amountGLPToRedeem > maxRedeem) {
            amountGLPToRedeem = maxRedeem;
        }

        if (amountGLPToRedeem == 0) {
            return 0;
        }

        lendingPool.removeCollateral(amountGLPToRedeem, address(this));
        require(wrappedGLP.withdrawTo(address(this), amountGLPToRedeem));

        uint256 usdcReceived = glpRewardRouterV2.unstakeAndRedeemGlp(
            lendingPool.asset(),
            amountGLPToRedeem,
            0,
            address(this)
        );

        // Use USDC to repay lending pool
        SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(lendingPool.asset()), address(lendingPool), usdcReceived);
        lendingPool.repay(usdcReceived, address(this));
        lendingPool.repayCost(amount - usdcReceived, address(this));

        return usdcReceived;
    }

    function _deposit(uint256 amount) internal {
        SafeERC20Upgradeable.safeTransferFrom(sGLP, msg.sender, address(this), amount);
        _wrapAddCollateral(amount);

        glpEquity += amount;
    }

    function _wrapAddCollateral(uint256 amount) internal {
        SafeERC20Upgradeable.safeApprove(sGLP, address(wrappedGLP), amount);
        require(wrappedGLP.depositFor(address(this), amount));

        SafeERC20Upgradeable.safeIncreaseAllowance(
            IERC20Upgradeable(address(wrappedGLP)),
            address(lendingPool),
            amount
        );
        lendingPool.addCollateral(amount, address(this));
    }

    function _withdrawTo(address account, uint256 amount) internal {
        glpEquity -= amount;

        lendingPool.removeCollateral(amount, address(this));
        require(wrappedGLP.withdrawTo(account, amount));
    }

    function _buyGLP(address token, uint256 amount, bool addEquity) internal {
        SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(token), glpRewardRouterV2.glpManager(), amount);
        uint256 glpMinted = glpRewardRouterV2.mintAndStakeGlp(token, amount, 0, 0);
        _wrapAddCollateral(glpMinted);

        if (addEquity) {
            glpEquity += glpMinted;
        }
    }

    function _repayWithWETH(uint256 amount) internal {
        uint256 usdcAmount = _swapWETHToUSDC(amount);

        SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(lendingPool.asset()), address(lendingPool), usdcAmount);
        lendingPool.repay(usdcAmount, address(this));
    }

    function _swapWETHToUSDC(uint256 amountIn) internal returns (uint256) {
        SafeERC20Upgradeable.safeApprove(weth, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: lendingPool.asset(),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 amountOut = swapRouter.exactInputSingle(params);

        return amountOut;
    }

    function _getCollateralState(
        uint256 withdrawGlpAmount
    ) internal view returns (uint256 collateralRatio, uint256 collateralValue, uint256 borrowValue) {
        (collateralValue, borrowValue) = lendingPool.getAccountLiquiditySimulate(
            address(this),
            0,
            0,
            0,
            withdrawGlpAmount
        );

        if (borrowValue == 0) {
            collateralRatio = type(uint256).max;
        } else {
            collateralRatio = collateralValue.mulDiv(1e18, borrowValue);
        }
    }

    function _collateralRatioAdjustmentDown(
        uint256 collateralValue,
        uint256 borrowValue,
        uint256 targetCollateralRatio
    ) internal view returns (uint256) {
        uint256 glpDebt_ = lendingPool.userCollateralAmount(address(this)) - glpEquity;
        uint256 glpDebtUSD = glpDebt_.mulDiv(wrappedGLP.getPrice(), 1e18);
        uint256 totalValue = collateralValue - glpDebtUSD + borrowValue;
        uint256 targetValue = targetCollateralRatio.mulDiv(borrowValue, 1e18);

        if (targetValue <= totalValue) {
            return 0;
        }

        uint256 intermediateValue1 = totalValue > targetValue ? totalValue - targetValue : targetValue - totalValue;
        uint256 intermediateValue2 = (targetCollateralRatio - 1e18);

        return intermediateValue1.mulDiv(1e18, intermediateValue2);
    }

    function _collateralRatioAdjustmentUp(
        uint256 collateralValue,
        uint256 borrowValue,
        uint256 targetCollateralRatio
    ) internal view returns (uint256) {
        uint256 glpDebt_ = lendingPool.userCollateralAmount(address(this)) - glpEquity;
        uint256 glpDebtUSD = glpDebt_.mulDiv(wrappedGLP.getPrice(), 1e18);
        uint256 totalValue = collateralValue - glpDebtUSD + borrowValue;
        uint256 targetValue = targetCollateralRatio.mulDiv(borrowValue, 1e18);
        if (targetValue >= totalValue) {
            return 0;
        }

        uint256 intermediateValue1 = totalValue > targetValue ? totalValue - targetValue : targetValue - totalValue;
        uint256 intermediateValue2 = (targetCollateralRatio - 1e18);
        return intermediateValue1.mulDiv(1e18, intermediateValue2);
    }

    // Returns USDC equivalent for amount of GLP
    function _glpToUSDC(uint256 amount) internal view returns (uint256) {
        IGLPManager glpManager = IGLPManager(glpRewardRouterV2.glpManager());

        AggregatorV3Interface chainlinkPriceFeed = AggregatorV3Interface(lendingPool.lendingAssetPriceFeed());

        (uint80 roundId, int256 chainlinkUsdcPrice, , uint256 updatedAt, uint80 answeredInRound) = chainlinkPriceFeed
            .latestRoundData();
        require(answeredInRound >= roundId, "Stale price: outdated round");
        require(updatedAt > 0, "Incomplete round");
        require(
            block.timestamp <= updatedAt + lendingPool.lendingAssetRefreshRate(),
            "Stale price: outside oracle refresh rate"
        );
        require(chainlinkUsdcPrice > 0, "Chainlink price <= 0");

        uint256 glpPrice = glpManager.getPrice(true);

        uint256 scale = 10 **
            (sGLP.decimals() +
                30 -
                chainlinkPriceFeed.decimals() -
                IERC20MetadataUpgradeable(lendingPool.asset()).decimals());

        uint256 usdcAmount = amount.mulDiv(glpPrice, uint256(chainlinkUsdcPrice));

        return (usdcAmount + (scale - 1)) / scale;
    }

    function _usdcToGLPWithCost(uint256 amount) internal view returns (uint256, uint256) {
        IGLPManager glpManager = IGLPManager(glpRewardRouterV2.glpManager());
        IGLPVault glpVault = IGLPVault(glpManager.vault());
        address asset = lendingPool.asset();

        amount += 2;

        uint256 glpPrice = glpManager.getPrice(false);

        uint256 usdcPrice = glpVault.getMaxPrice(asset) * 1e12;

        uint256 usdgAmount = amount.mulDiv(usdcPrice, 1e30, MathUpgradeable.Rounding.Down);

        uint256 glpAmount = amount.mulDiv(usdcPrice, glpPrice, MathUpgradeable.Rounding.Down);

        uint256 feeBasisPoints = glpVault.getFeeBasisPoints(
            asset,
            usdgAmount,
            glpVault.mintBurnFeeBasisPoints(),
            glpVault.taxBasisPoints(),
            false
        );

        uint256 glpRequired = (glpAmount * 1e4) / (1e4 - feeBasisPoints);

        return (glpRequired, glpRequired - glpAmount);
    }

    function _glpToUSDCWithCost(uint256 amount) internal view returns (uint256) {
        IGLPManager glpManager = IGLPManager(glpRewardRouterV2.glpManager());
        IGLPVault glpVault = IGLPVault(glpManager.vault());
        address asset = lendingPool.asset();

        amount += 2;

        uint256 glpPrice = glpManager.getPrice(false);

        uint256 usdcPrice = glpVault.getMaxPrice(asset);

        uint256 usdgAmount = amount.mulDiv(glpPrice, 1e30, MathUpgradeable.Rounding.Down);

        uint256 usdcAmount = usdgAmount.mulDiv(1e30, usdcPrice) / 1e12;

        uint256 feeBasisPoints = glpVault.getFeeBasisPoints(
            asset,
            usdgAmount,
            glpVault.mintBurnFeeBasisPoints(),
            glpVault.taxBasisPoints(),
            false
        );

        uint256 usdcReceive = ((usdcAmount * (1e4 - feeBasisPoints)) / 1e4);

        return usdcReceive;
    }

    // Returns amount of GLP required to unstakeAndRedeem amount of USDC (in USD)
    function _usdToGLPWithCost(uint256 amount) internal view returns (uint256, uint256) {
        return _usdcToGLPWithCost(_usdToUSDC(amount));
    }

    function _usdToGLP(uint256 amount) internal view returns (uint256) {
        IGLPManager glpManager = IGLPManager(glpRewardRouterV2.glpManager());

        uint256 glpPrice = glpManager.getPrice(false);

        uint256 glpAmount = amount.mulDiv(glpPrice, 1e30, MathUpgradeable.Rounding.Down);

        return glpAmount;
    }

    // Returns amount of USDC for amount of USD
    function _usdToUSDC(uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface chainlinkPriceFeed = AggregatorV3Interface(lendingPool.lendingAssetPriceFeed());

        (uint80 roundId, int256 chainlinkUsdcPrice, , uint256 updatedAt, uint80 answeredInRound) = chainlinkPriceFeed
            .latestRoundData();
        require(answeredInRound >= roundId, "Stale price");
        require(updatedAt > 0, "Incomplete round");
        require(
            block.timestamp <= updatedAt + lendingPool.lendingAssetRefreshRate(),
            "Stale price: outside oracle refresh rate"
        );
        require(chainlinkUsdcPrice > 0, "Chainlink price <= 0");

        return
            amount.mulDiv(
                10 ** chainlinkPriceFeed.decimals(),
                uint256(chainlinkUsdcPrice) * (10 ** (18 - IERC20MetadataUpgradeable(lendingPool.asset()).decimals()))
            );
    }

    // Returns amount of ETH for amount of USD
    function _usdToWETH(uint256 amount) internal view returns (uint256) {
        (uint80 roundId, int256 chainlinkETHPrice, , uint256 updatedAt, uint80 answeredInRound) = ethUSDOracle
            .latestRoundData();
        require(answeredInRound >= roundId, "Stale price: outdated round");
        require(updatedAt > 0, "Incomplete round");
        require(block.timestamp <= updatedAt + ethUSDOracleRefreshRate, "Stale price: outside oracle refresh rate");
        require(chainlinkETHPrice > 0, "Chainlink price <= 0");

        return amount.mulDiv(10 ** ethUSDOracle.decimals(), uint256(chainlinkETHPrice));
    }
}

