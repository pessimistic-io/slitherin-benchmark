// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./MathUpgradeable.sol";
import "./AggregatorV3Interface.sol";
import "./IWrappedGLP.sol";
import "./IStrategy.sol";
import "./LendingPoolStorage.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract LendingPool is
    Initializable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    LendingPoolStorage
{
    using MathUpgradeable for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lendingAsset,
        address _collateralAsset,
        address _strategy,
        string calldata _name,
        string calldata _symbol,
        bytes calldata params
    ) public virtual initializer {
        __LendingPool_init(_lendingAsset, _collateralAsset, _strategy, _name, _symbol, params);
    }

    function __LendingPool_init(
        address _lendingAsset,
        address _collateralAsset,
        address _strategy,
        string calldata _name,
        string calldata _symbol,
        bytes calldata params
    ) public onlyInitializing {
        require(_lendingAsset != address(0), "lending asset is the zero address");
        require(_collateralAsset != address(0), "collateral asset is the zero address");

        __ERC4626_init(IERC20MetadataUpgradeable(_lendingAsset));
        __ERC20_init(_name, _symbol);
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        (
            uint256 _collateralFactor,
            uint256 _interestRateBase,
            uint256 _interestRateSlope1,
            uint256 _interestRateSlope2,
            uint256 _interestRateUtilizationBound
        ) = abi.decode(params, (uint256, uint256, uint256, uint256, uint256));

        collateralAsset = IERC20MetadataUpgradeable(_collateralAsset);
        collateralFactor = _collateralFactor;
        interestRateBase = _interestRateBase;
        interestRateSlope1 = _interestRateSlope1;
        interestRateSlope2 = _interestRateSlope2;
        interestRateUtilizationBound = _interestRateUtilizationBound;
        strategy = IStrategy(_strategy);
        collateralScale = 10 ** collateralAsset.decimals();
        lastAccrueTime = block.timestamp;
        lendingAssetPriceFeed = AggregatorV3Interface(
            0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3 // Arbitrum mainnet: USDC/USD
        );
        lendingAssetRefreshRate = 1 days; // Default/Fallback USDC/USD refresh rate of 24hrs
        assetScale = 10 ** decimals();
        totalAccumulatedInterestRate = FACTOR;
    }

    modifier onlyStrategy() {
        require(msg.sender == address(strategy), "unauthorized");
        _;
    }

    // ADMIN METHODS

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setContract(Contracts c, address cAddress) external onlyOwner {
        require(cAddress != address(0));

        if (c == Contracts.PriceFeedAgregatorV3) {
            lendingAssetPriceFeed = AggregatorV3Interface(cAddress);
            return;
        }
    }

    function setCollateralFactor(uint256 factor) public onlyOwner {
        require(collateralFactor != factor, "collateral factor already set");

        collateralFactor = factor;
    }

    function setLendingAssetRefreshRate(uint256 rate) public onlyOwner {
        require(rate > 0, "lending asset refresh rate must be greater than 0");

        lendingAssetRefreshRate = rate;
    }

    function setInterestRateParameters(
        uint256 _interestRateBase,
        uint256 _interestRateSlope1,
        uint256 _interestRateSlope2,
        uint256 _interestRateUtilizationBound
    ) public onlyOwner {
        if (interestRateBase != _interestRateBase) {
            interestRateBase = _interestRateBase;
        }

        if (interestRateSlope1 != _interestRateSlope1) {
            interestRateSlope1 = _interestRateSlope1;
        }

        if (interestRateSlope2 != _interestRateSlope2) {
            interestRateSlope2 = _interestRateSlope2;
        }

        if (interestRateUtilizationBound != _interestRateUtilizationBound) {
            interestRateUtilizationBound = _interestRateUtilizationBound;
        }
    }

    // LENDER METHODS

    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + totalBorrowed;
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);

        return strategy.previewWithdrawLentAsset(assets);
    }

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        _accrue();

        if (assets == type(uint256).max) {
            assets = IERC20Upgradeable(asset()).balanceOf(msg.sender);
        }

        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 shares = previewDeposit(assets);
        require(shares > 0, "ERC4626: cannot mint 0 shares"); // We need to check for 0 since previewDeposit rounds down

        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _accrue();

        if (shares == type(uint256).max) {
            shares = maxRedeem(owner);
        }

        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        require(assets > 0, "ERC4626: cannot redeem 0 assets"); // We need to check for 0 since previewRedeem rounds down

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        _accrue();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _accrue();

        if (assets == type(uint256).max) {
            assets = maxWithdraw(owner);
        }

        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = _convertToShares(assets, MathUpgradeable.Rounding.Up);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    // BORROWER METHODS

    function addCollateral(uint256 amount, address receiver) public virtual whenNotPaused onlyStrategy {
        _addCollateral(amount, receiver);
    }

    function removeCollateral(uint256 amount, address receiver) public virtual whenNotPaused onlyStrategy {
        _removeCollateral(amount, receiver);
    }

    function borrow(uint256 amount) public virtual whenNotPaused onlyStrategy {
        _borrow(amount);
    }

    function repay(uint256 amount, address borrower) public virtual whenNotPaused onlyStrategy {
        _repay(amount, borrower, false);
    }

    function repayCost(uint256 amount, address borrower) public virtual whenNotPaused onlyStrategy {
        _repay(amount, borrower, true);
    }

    function getAccountLiquidity(address account) public view returns (uint256 collateralValue, uint256 borrowValue) {
        (collateralValue, borrowValue) = _getAccountLiquidity(account, 0, 0, 0, 0);
    }

    function getAccountLiquiditySimulate(
        address account,
        uint256 moreBorrow,
        uint256 lessBorrow,
        uint256 moreCollateral,
        uint256 lessCollateral
    ) public view returns (uint256 collateralValue, uint256 borrowValue) {
        (collateralValue, borrowValue) = _getAccountLiquidity(
            account,
            moreBorrow,
            lessBorrow,
            moreCollateral,
            lessCollateral
        );
        borrowValue = borrowValue.mulDiv(collateralScale, assetScale);
    }

    function getAccountBalances(
        address account
    ) public view returns (uint256 collateralTokens, uint256 borrowedTokens) {
        BorrowState memory userBorrowState = userBorrowState[account];

        borrowedTokens = userBorrowState.principal == 0
            ? 0
            : userBorrowState.principal.mulDiv(
                totalAccumulatedInterestRate,
                userBorrowState.lastAccumulatedInterestRate,
                MathUpgradeable.Rounding.Up
            );
        collateralTokens = userCollateralAmount[account];
    }

    function getUtilization() public view returns (uint256) {
        uint256 totalAssets_ = totalAssets();

        return totalAssets_ == 0 ? 0 : totalBorrowed.mulDiv(FACTOR, totalAssets_);
    }

    function getInterestRate() public view returns (uint256) {
        uint256 utilization = getUtilization();
        uint256 interestRate = interestRateBase;

        if (utilization <= interestRateUtilizationBound) {
            interestRate += utilization.mulDiv(interestRateSlope1, FACTOR);
        } else {
            interestRate += interestRateUtilizationBound.mulDiv(interestRateSlope1, FACTOR);
            interestRate += interestRateSlope2.mulDiv((utilization - interestRateUtilizationBound), FACTOR);
        }

        return interestRate;
    }

    function accrue() public whenNotPaused {
        _accrue();
    }

    // INTERNAL METHODS

    function _addCollateral(uint256 amount, address receiver) internal {
        // Steps:
        // - accrue
        // - transfer collateral asset to address(this)
        // - update user collateral balance

        _accrue();

        SafeERC20Upgradeable.safeTransferFrom(collateralAsset, msg.sender, address(this), amount);
        userCollateralAmount[receiver] += amount;
    }

    function _removeCollateral(uint256 amount, address receiver) internal {
        // Steps:
        // - accrue()
        // - checkLiquidity() and revert if needed
        // - check user balance of collateral is higher than remove amount
        // - subtract amount from user collateral amount
        // - transfer collateral asset back to msg.sender

        _accrue();

        // don't check liquifity on removeCollateral to allow flashloan like repayments
        // require(_checkLiquidity(msg.sender, 0, amount), "not collateralized");

        uint256 userCollateral = userCollateralAmount[msg.sender];
        require(userCollateral >= amount, "insufficient collateral");

        userCollateralAmount[msg.sender] = userCollateral - amount;
        SafeERC20Upgradeable.safeTransfer(collateralAsset, receiver, amount);
    }

    function _borrow(uint256 amount) internal {
        // Steps:
        // - accrue()
        // - checkLiquidity() and revert if needed
        // - check enough of asset to meet requested borrow amount
        // - add to totalBorrow amount
        // - add to user borrow amount
        // - transfer asset to borrower

        _accrue();

        require(_checkLiquidity(msg.sender, amount, 0), "not collateralized");

        require(super.totalAssets() >= amount, "insufficient assets for borrow");

        uint256 totalAccumulatedInterestRate = totalAccumulatedInterestRate;

        BorrowState memory userBorrowState_ = userBorrowState[msg.sender];
        uint256 currentPrincipalAmount = userBorrowState_.principal == 0
            ? 0
            : userBorrowState_.principal.mulDiv(
                totalAccumulatedInterestRate,
                userBorrowState_.lastAccumulatedInterestRate,
                MathUpgradeable.Rounding.Down
            );

        userBorrowState[msg.sender].principal = currentPrincipalAmount + amount;
        userBorrowState[msg.sender].lastAccumulatedInterestRate = totalAccumulatedInterestRate;

        totalBorrowed += amount;

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), msg.sender, amount);
    }

    function _repay(uint256 amount, address borrower, bool internalTransfer) internal {
        // Steps:
        // - accrue()
        // - transfer collateral asset from sender to address(this)
        // - subtract from totalBorrow amount
        // - subtract from user borrow amount

        _accrue();

        uint256 totalAccumulatedInterestRate = totalAccumulatedInterestRate;

        BorrowState memory userBorrowState_ = userBorrowState[borrower];
        uint256 currentPrincipalAmountUp = userBorrowState_.principal == 0
            ? 0
            : userBorrowState_.principal.mulDiv(
                totalAccumulatedInterestRate,
                userBorrowState_.lastAccumulatedInterestRate,
                MathUpgradeable.Rounding.Up
            );

        uint256 currentPrincipalAmountDown = userBorrowState_.principal == 0
            ? 0
            : userBorrowState_.principal.mulDiv(
                totalAccumulatedInterestRate,
                userBorrowState_.lastAccumulatedInterestRate,
                MathUpgradeable.Rounding.Down
            );

        if (amount > currentPrincipalAmountUp) {
            amount = currentPrincipalAmountUp;
        }

        if (!internalTransfer) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(asset()), msg.sender, address(this), amount);
        }

        uint256 remaining = currentPrincipalAmountUp - amount;

        userBorrowState[borrower].principal = remaining;
        userBorrowState[borrower].lastAccumulatedInterestRate = totalAccumulatedInterestRate;

        if (currentPrincipalAmountDown > totalBorrowed) {
            currentPrincipalAmountDown = totalBorrowed;
        }

        totalBorrowed = totalBorrowed - currentPrincipalAmountDown + remaining;
    }

    function _checkLiquidity(address account, uint256 moreBorrow, uint256 lessCollateral) internal view returns (bool) {
        // Steps:
        // - check if account liquidity is below threshold ratio. This should include the new borrow amount (on borrow) or the reduced collateral amount (on remove collateral)

        (uint256 collateralValue, uint256 borrowValue) = _getAccountLiquidity(
            account,
            moreBorrow,
            0,
            0,
            lessCollateral
        );

        collateralValue = collateralValue.mulDiv(collateralFactor, collateralScale);

        return collateralValue >= borrowValue.mulDiv(collateralScale, assetScale);
    }

    function _getAccountLiquidity(
        address account,
        uint256 moreBorrow,
        uint256 lessBorrow,
        uint256 moreCollateral,
        uint256 lessCollateral
    ) internal view returns (uint256 collateralValue, uint256 borrowValue) {
        // Steps:
        // - get current price of collateral
        // - get current asset price from Oracle
        // - calculate value of borrowed amount
        // - calculate value of collateral amount

        uint256 collateralPrice = IWrappedGLP(address(collateralAsset)).getPrice();

        (
            uint80 roundId,
            int256 chainlinkAssetPrice,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = lendingAssetPriceFeed.latestRoundData();
        require(answeredInRound >= roundId, "Stale price: outdated round");
        require(updatedAt > 0, "Incomplete round");
        require(block.timestamp <= updatedAt + lendingAssetRefreshRate, "Stale price: outside oracle refresh rate");
        require(chainlinkAssetPrice > 0, "Chainlink price <= 0");

        BorrowState memory userBorrowState = userBorrowState[account];
        uint256 userCollateralAmount = userCollateralAmount[account];

        if (moreCollateral > 0) {
            userCollateralAmount += moreCollateral;
        }
        if (lessCollateral > 0) {
            if (userCollateralAmount < lessCollateral) {
                userCollateralAmount = 0;
            } else {
                userCollateralAmount -= lessCollateral;
            }
        }

        uint256 currentPrincipalAmount = userBorrowState.principal == 0
            ? 0
            : userBorrowState.principal.mulDiv(
                totalAccumulatedInterestRate,
                userBorrowState.lastAccumulatedInterestRate,
                MathUpgradeable.Rounding.Up
            );

        if (moreBorrow > 0) {
            currentPrincipalAmount += moreBorrow;
        }
        if (lessBorrow > 0) {
            if (currentPrincipalAmount < lessBorrow) {
                currentPrincipalAmount = 0;
            } else {
                currentPrincipalAmount -= lessBorrow;
            }
        }

        borrowValue = currentPrincipalAmount.mulDiv(
            uint256(chainlinkAssetPrice),
            10 ** lendingAssetPriceFeed.decimals()
        );
        collateralValue = userCollateralAmount.mulDiv(collateralPrice, collateralScale);
    }

    function _accrue() internal {
        // Steps:
        // - increase totalBorrowed by interest accumulated
        // - increase TotalInterestRate by totalInterestRate

        strategy.claimRewards();

        uint256 now_ = block.timestamp;
        uint256 timeElapsed = now_ - lastAccrueTime;
        if (timeElapsed > 0) {
            uint256 totalInterestRate_ = totalAccumulatedInterestRate;
            uint256 totalBorrowed_ = totalBorrowed;

            uint256 periodInterestRate = getInterestRate() * timeElapsed;
            uint256 totalInterestAccrued = periodInterestRate.mulDiv(
                totalBorrowed_,
                FACTOR,
                MathUpgradeable.Rounding.Down
            );
            uint256 totalInterestRate = periodInterestRate.mulDiv(totalInterestRate_, FACTOR);

            totalBorrowed = totalBorrowed_ + totalInterestAccrued;
            totalAccumulatedInterestRate = totalInterestRate_ + totalInterestRate;
            lastAccrueTime = now_;
        }
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        uint256 assetsAvailable = super.totalAssets();

        if (assetsAvailable < assets) {
            uint256 assetsMinusCost = strategy.prepareWithdrawLendingAsset(assets - assetsAvailable);
            if (assets > assetsAvailable + assetsMinusCost) {
                assets = assetsAvailable + assetsMinusCost;
            }
        }

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

