// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./ERC4626.sol";
import "./Ownable.sol";

import "./IRewardTracker.sol";
import "./IStakingYieldPool.sol";
import "./ICamelotDex.sol";

import "./console.sol";

contract AcidVault is ERC4626, Ownable {
    IRewardTracker public rewardTracker;
    IStakingYieldPool public stakingYieldPool;
    ICamelotDex public camelotDex;
    address public treasury;
    uint256 public treasuryFeePercentage = 1000;

    address private immutable wstETH;
    address private immutable wETH;
    uint256 private minRewardToSwap = 1e15;
    uint256 private slippagePercentage = 500;
    uint256 private constant HUNDRED_PERCENT = 10000;

    RatePoint[] private ratePoints;
    address[] private swapPath;

    struct RatePoint {
        uint256 rate;
        uint256 timestamp;
    }

    constructor(
        address _asset,
        address _rewardTracker,
        address _stakingYieldPool,
        address _wstETH,
        address _camelotDex,
        address _wETH,
        RatePoint[] memory _initialRatePoints
    ) ERC4626(IERC20(_asset)) ERC20("Acid Trip sAcid", "atsAcid") {
        rewardTracker = IRewardTracker(_rewardTracker);
        stakingYieldPool = IStakingYieldPool(_stakingYieldPool);
        wstETH = _wstETH;
        wETH = _wETH;
        camelotDex = ICamelotDex(_camelotDex);
        for (uint256 i = 0; i < _initialRatePoints.length; i++) {
            ratePoints.push(_initialRatePoints[i]);
        }

        swapPath = new address[](3);
        swapPath[0] = wstETH;
        swapPath[1] = wETH;
        swapPath[2] = asset();

        IERC20(asset()).approve(address(rewardTracker), type(uint256).max);
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
        require(_treasuryFeePercentage <= 5000, "AcidVault: treasury fee percentage must be less than or equal to 50%");
        treasuryFeePercentage = _treasuryFeePercentage;
    }

    function setMinRewardToSwap(uint256 _minRewardToSwap) external onlyOwner {
        minRewardToSwap = _minRewardToSwap;
    }

    function setSlippagePercentage(uint256 _slippagePercentage) external onlyOwner {
        slippagePercentage = _slippagePercentage;
    }

    function depositWithRewards(uint256 amount, address to) public returns (uint256) {
        require(amount > 0, "AcidVault: deposit amount must be greater than 0");
        require(to != address(0), "AcidVault: deposit to the zero address");

        _collectRewards();

        return deposit(amount, to);
    }

    function deposit(uint256 amount, address to) public override returns (uint256) {
        require(amount > 0, "AcidVault: deposit amount must be greater than 0");
        require(to != address(0), "AcidVault: deposit to the zero address");

        uint256 shares = ERC4626.deposit(amount, to);

        uint256 totalToDeposit = IERC20(asset()).balanceOf(address(this));
        rewardTracker.deposit(totalToDeposit, 0);

        return shares;
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        require(shares > 0, "AcidVault: mint shares must be greater than 0");
        require(receiver != address(0), "AcidVault: mint to the zero address");
        require(previewMint(shares) > 0, "AcidVault: mint amount must be greater than 0");

        uint256 assets = ERC4626.mint(shares, receiver);

        uint256 totalToDeposit = IERC20(asset()).balanceOf(address(this));
        rewardTracker.deposit(totalToDeposit, 0);

        return assets;
    }

    function redeemWithRewards(uint256 shares, address receiver, address owner) public returns (uint256) {
        require(shares > 0, "AcidVault: redeem shares must be greater than 0");
        require(receiver != address(0), "AcidVault: redeem to the zero address");

        _collectRewards();

        return redeem(shares, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        require(shares > 0, "AcidVault: redeem shares must be greater than 0");
        require(receiver != address(0), "AcidVault: redeem to the zero address");

        uint256 availableAssets = IERC20(asset()).balanceOf(address(this));
        uint256 requiredAssets = previewRedeem(shares);

        if (requiredAssets > availableAssets) {
            rewardTracker.withdraw(requiredAssets - availableAssets, 0);
            ERC4626.redeem(shares, receiver, owner);
        } else {
            ERC4626.redeem(shares, receiver, owner);
            _depositRewards();
        }

        return requiredAssets;
    }

    function withdrawWithRewards(uint256 assets, address receiver, address owner) public returns (uint256) {
        require(assets > 0, "AcidVault: withdraw assets must be greater than 0");
        require(receiver != address(0), "AcidVault: withdraw to the zero address");

        _collectRewards();

        return withdraw(assets, receiver, owner);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        require(assets > 0, "AcidVault: withdraw assets must be greater than 0");
        require(receiver != address(0), "AcidVault: withdraw to the zero address");

        uint256 availableAssets = IERC20(asset()).balanceOf(address(this));
        uint256 shares = 0;

        if (assets > availableAssets) {
            rewardTracker.withdraw(assets - availableAssets, 0);
            shares = ERC4626.withdraw(assets, receiver, owner);
        } else {
            shares = ERC4626.withdraw(assets, receiver, owner);
            _depositRewards();
        }

        return shares;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 earned = stakingYieldPool.earned(address(this)) + IERC20(wstETH).balanceOf(address(this));
        uint256 rewardEarned = 0;

        if (earned > 0) {
            uint256[] memory rewards = camelotDex.getAmountsOut(earned, swapPath);
            if (treasury == address(0)) {
                rewardEarned = rewards[2];
            } else {
                rewardEarned = rewards[2] * (HUNDRED_PERCENT - treasuryFeePercentage) / HUNDRED_PERCENT;
            }
        }

        return IERC20(address(rewardTracker)).balanceOf(address(this)) + IERC20(asset()).balanceOf(address(this))
            + rewardEarned;
    }

    function collectRewards() public {
        _collectRewards();
        _depositRewards();
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

    function _depositRewards() internal {
        uint256 totalToDeposit = IERC20(asset()).balanceOf(address(this));
        if (totalToDeposit > 0) {
            rewardTracker.deposit(totalToDeposit, 0);
        }
    }

    function _collectRewards() internal {
        _addRatePoint();

        stakingYieldPool.getReward();
        uint256 reward = IERC20(wstETH).balanceOf(address(this));

        if (reward > minRewardToSwap) {
            IERC20(wstETH).approve(address(camelotDex), reward);
            uint256 acidBalanceBefore = IERC20(asset()).balanceOf(address(this));
            uint256 minAmountOut =
                twap() * (HUNDRED_PERCENT - slippagePercentage) * reward / minRewardToSwap / HUNDRED_PERCENT;

            camelotDex.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                reward, minAmountOut, swapPath, address(this), address(0), block.timestamp
            );

            if (treasury != address(0)) {
                uint256 acidBalanceAfter = IERC20(asset()).balanceOf(address(this));
                uint256 acidEarned = acidBalanceAfter - acidBalanceBefore;
                uint256 fee = acidEarned * treasuryFeePercentage / HUNDRED_PERCENT;

                if (fee > 0) {
                    IERC20(asset()).transfer(treasury, fee);
                }
            }
        }
    }

    function _addRatePoint() internal {
        uint256 timeElapsed = block.timestamp - ratePoints[ratePoints.length - 1].timestamp;
        if (timeElapsed < 5 minutes) {
            return;
        }

        uint256[] memory rewards = camelotDex.getAmountsOut(minRewardToSwap, swapPath);
        if (rewards[2] > 0) {
            RatePoint memory ratePoint = RatePoint({timestamp: block.timestamp, rate: rewards[2]});
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
}

