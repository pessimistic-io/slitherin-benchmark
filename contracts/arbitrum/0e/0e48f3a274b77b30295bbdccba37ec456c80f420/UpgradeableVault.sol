// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.19;

import "./IERC20Upgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./MathUpgradeable.sol";

import "./IRewardTracker.sol";
import "./IStakingYieldPool.sol";
import "./ICamelotDex.sol";

abstract contract UpgradeableVault is ERC4626Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using MathUpgradeable for uint256;

    uint256 internal constant HUNDRED_PERCENT = 10000;

    IRewardTracker public rewardTracker;
    IStakingYieldPool public stakingYieldPool;
    ICamelotDex public camelotDex;
    address public treasury;
    uint256 public treasuryFeePercentage;
    address internal wstETH;
    address internal wETH;
    address internal esAcid;
    uint256 internal minToSwap;
    uint256 internal slippagePercentage;
    RatePoint[] internal ratePoints;
    address[] internal swapPath;
    uint256[50] private __gap;

    struct RatePoint {
        uint256 rate;
        uint256 timestamp;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _asset,
        address _rewardTracker,
        address _stakingYieldPool,
        address _wstETH,
        address _camelotDex,
        address _wETH,
        address _esAcid,
        string memory _sharesName,
        string memory _sharesSymbol,
        RatePoint[] memory _initialRatePoints
    ) public virtual initializer {
        __ERC4626_init(IERC20Upgradeable(_asset));
        __ERC20_init(_sharesName, _sharesSymbol);
        __Ownable_init();
        __UUPSUpgradeable_init();

        rewardTracker = IRewardTracker(_rewardTracker);
        stakingYieldPool = IStakingYieldPool(_stakingYieldPool);
        wstETH = _wstETH;
        wETH = _wETH;
        esAcid = _esAcid;
        camelotDex = ICamelotDex(_camelotDex);

        for (uint256 i = 0; i < _initialRatePoints.length; i++) {
            ratePoints.push(_initialRatePoints[i]);
        }

        swapPath = new address[](3);
        swapPath[0] = wstETH;
        swapPath[1] = wETH;
        swapPath[2] = asset();

        treasuryFeePercentage = 1000;
        minToSwap = 1e15;
        slippagePercentage = 500;

        IERC20Upgradeable(asset()).approve(address(rewardTracker), type(uint256).max);
    }

    function setRewardTracker(address _rewardTracker) external onlyOwner {
        rewardTracker = IRewardTracker(_rewardTracker);
    }

    function setStakingYieldPool(address _stakingYieldPool) external onlyOwner {
        stakingYieldPool = IStakingYieldPool(_stakingYieldPool);
    }

    function setCamelotDex(address _camelotDex) external onlyOwner {
        camelotDex = ICamelotDex(_camelotDex);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setTreasuryFeePercentage(uint256 _treasuryFeePercentage) external onlyOwner {
        require(
            _treasuryFeePercentage <= 5000,
            "UpgradeableVault: treasury fee percentage must be less than or equal to 50%"
        );
        treasuryFeePercentage = _treasuryFeePercentage;
    }

    function setMinToSwap(uint256 _minToSwap) external onlyOwner {
        minToSwap = _minToSwap;
    }

    function setSlippagePercentage(uint256 _slippagePercentage) external onlyOwner {
        slippagePercentage = _slippagePercentage;
    }

    function depositWithRewards(uint256 amount, address to) public returns (uint256) {
        require(amount > 0, "UpgradeableVault: deposit amount must be greater than 0");
        require(to != address(0), "UpgradeableVault: deposit to the zero address");

        _collectRewards();

        return deposit(amount, to);
    }

    function deposit(uint256 amount, address to) public override returns (uint256) {
        require(amount > 0, "UpgradeableVault: deposit amount must be greater than 0");
        require(to != address(0), "UpgradeableVault: deposit to the zero address");

        uint256 shares = ERC4626Upgradeable.deposit(amount, to);

        _depositAssets();

        return shares;
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        require(shares > 0, "UpgradeableVault: mint shares must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: mint to the zero address");
        require(previewMint(shares) > 0, "UpgradeableVault: mint amount must be greater than 0");

        uint256 assets = ERC4626Upgradeable.mint(shares, receiver);

        _depositAssets();

        return assets;
    }

    function redeemWithRewards(uint256 shares, address receiver, address owner) public returns (uint256) {
        require(shares > 0, "UpgradeableVault: redeem shares must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: redeem to the zero address");

        _collectRewards();

        return redeem(shares, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        require(shares > 0, "UpgradeableVault: redeem shares must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: redeem to the zero address");

        uint256 availableAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        uint256 requiredAssets = previewRedeem(shares);

        if (requiredAssets > availableAssets) {
            _withdrawAssets(requiredAssets - availableAssets);
            ERC4626Upgradeable.redeem(shares, receiver, owner);
        } else {
            ERC4626Upgradeable.redeem(shares, receiver, owner);
            _depositAssets();
        }

        return requiredAssets;
    }

    function withdrawWithRewards(uint256 assets, address receiver, address owner) public returns (uint256) {
        require(assets > 0, "UpgradeableVault: withdraw assets must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: withdraw to the zero address");

        _collectRewards();

        return withdraw(assets, receiver, owner);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        require(assets > 0, "UpgradeableVault: withdraw assets must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: withdraw to the zero address");

        uint256 availableAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        uint256 shares = 0;

        if (assets > availableAssets) {
            _withdrawAssets(assets - availableAssets);
            shares = ERC4626Upgradeable.withdraw(assets, receiver, owner);
        } else {
            shares = ERC4626Upgradeable.withdraw(assets, receiver, owner);
            _depositAssets();
        }

        return shares;
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 earned = stakingYieldPool.earned(address(this)) + IERC20Upgradeable(wstETH).balanceOf(address(this));
        uint256 rewardEarned = 0;

        if (earned > 0) {
            uint256[] memory rewards = camelotDex.getAmountsOut(earned, swapPath);
            if (treasury == address(0)) {
                rewardEarned = rewards[2];
            } else {
                rewardEarned = rewards[2] * (HUNDRED_PERCENT - treasuryFeePercentage) / HUNDRED_PERCENT;
            }
        }

        return IERC20Upgradeable(address(rewardTracker)).balanceOf(address(this))
            + IERC20Upgradeable(asset()).balanceOf(address(this)) + rewardEarned;
    }

    function collectRewards() public {
        _collectRewards();
        _depositAssets();
    }

    function twap() public view returns (uint256) {
        uint256 noPoints = ratePoints.length;
        uint256 timeElapsed = ratePoints[noPoints - 1].timestamp - ratePoints[0].timestamp;
        uint256 weightedTotal = 0;

        for (uint256 i = 0; i < noPoints; i++) {
            if (i == 0) {
                weightedTotal += ratePoints[i].rate;
            } else {
                weightedTotal += ratePoints[i].rate * (ratePoints[i].timestamp - ratePoints[i - 1].timestamp);
            }
        }

        if (timeElapsed == 0) {
            return weightedTotal;
        }

        return weightedTotal / timeElapsed;
    }

    function _depositAssets() internal virtual {
        uint256 totalToDeposit = IERC20Upgradeable(asset()).balanceOf(address(this));
        if (totalToDeposit > 0) {
            rewardTracker.deposit(totalToDeposit, 0);
        }
    }

    function _withdrawAssets(uint256 amount) internal virtual {
        rewardTracker.withdraw(amount, 0);
    }

    function _collectRewards() internal virtual {
        _addRatePoint();

        stakingYieldPool.getReward();
        uint256 reward = IERC20Upgradeable(wstETH).balanceOf(address(this));

        if (reward > minToSwap) {
            IERC20Upgradeable(wstETH).approve(address(camelotDex), reward);
            uint256 acidBalanceBefore = IERC20Upgradeable(asset()).balanceOf(address(this));
            uint256 minAmountOut =
                twap() * (HUNDRED_PERCENT - slippagePercentage) * reward / minToSwap / HUNDRED_PERCENT;

            camelotDex.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                reward, minAmountOut, swapPath, address(this), address(0), block.timestamp
            );

            if (treasury != address(0)) {
                uint256 acidBalanceAfter = IERC20Upgradeable(asset()).balanceOf(address(this));
                uint256 acidEarned = acidBalanceAfter - acidBalanceBefore;
                uint256 fee = acidEarned * treasuryFeePercentage / HUNDRED_PERCENT;

                if (fee > 0) {
                    IERC20Upgradeable(asset()).transfer(treasury, fee);
                }
            }
        }
    }

    function _addRatePoint() internal {
        uint256 timeElapsed = block.timestamp - ratePoints[ratePoints.length - 1].timestamp;
        if (timeElapsed < 5 minutes) {
            return;
        }

        uint256[] memory rewards = camelotDex.getAmountsOut(minToSwap, swapPath);
        if (rewards[rewards.length - 1] > 0) {
            RatePoint memory ratePoint = RatePoint({timestamp: block.timestamp, rate: rewards[rewards.length - 1]});
            if (ratePoints.length < 50) {
                ratePoints.push(ratePoint);
            } else {
                delete ratePoints[0];
                for (uint256 i = 0; i < ratePoints.length - 1; i++) {
                    ratePoints[i] = ratePoints[i + 1];
                }
                ratePoints.push(ratePoint);
            }
        }
    }

    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding)
        internal
        view
        override
        returns (uint256 shares)
    {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0)
            ? _initialConvertToShares(assets, rounding)
            : assets.mulDiv(supply, totalAssets(), rounding);
    }

    function _initialConvertToShares(uint256 assets, MathUpgradeable.Rounding /*rounding*/ )
        internal
        pure
        returns (uint256 shares)
    {
        return assets;
    }

    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding)
        internal
        view
        override
        returns (uint256 assets)
    {
        uint256 supply = totalSupply();
        return
            (supply == 0) ? _initialConvertToAssets(shares, rounding) : shares.mulDiv(totalAssets(), supply, rounding);
    }

    function _initialConvertToAssets(uint256 shares, MathUpgradeable.Rounding /*rounding*/ )
        internal
        pure
        returns (uint256 assets)
    {
        return shares;
    }

    function recoverToken(address[] calldata tokens) external onlyOwner {
        unchecked {
            for (uint8 i; i < tokens.length; i++) {
                _validateRecoverableToken(tokens[i]);
                IERC20Upgradeable(tokens[i]).transfer(msg.sender, IERC20Upgradeable(tokens[i]).balanceOf(address(this)));
            }
        }
    }

    function recoverETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function _validateRecoverableToken(address token) internal view virtual {
        require(token != address(rewardTracker), "Cannot recover sAcid");
        require(token != wstETH, "Cannot recover wstETH");
        require(token != address(asset()), "Cannot recover Acid");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

