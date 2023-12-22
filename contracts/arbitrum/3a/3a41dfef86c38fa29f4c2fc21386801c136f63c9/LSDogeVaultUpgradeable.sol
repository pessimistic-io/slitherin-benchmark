// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.19;

import "./UpgradeableVault.sol";

import "./ILSDStakingYieldPool.sol";

contract LSDogeVaultUpgradeable is UpgradeableVault {
    ILSDStakingYieldPool public lsdStakingYieldPool;

    function initialize(
        address _asset,
        address _stakingYieldPool,
        address _camelotDex,
        address _wETH,
        RatePoint[] memory _initialRatePoints
    ) public initializer {
        __ERC4626_init(IERC20Upgradeable(_asset));
        __ERC20_init("sLSDoge", "sLSDoge");
        __Ownable_init();
        __UUPSUpgradeable_init();

        lsdStakingYieldPool = ILSDStakingYieldPool(_stakingYieldPool);
        wETH = _wETH;
        camelotDex = ICamelotDex(_camelotDex);

        for (uint256 i = 0; i < _initialRatePoints.length; i++) {
            ratePoints.push(_initialRatePoints[i]);
        }

        swapPath = new address[](2);
        swapPath[0] = wETH;
        swapPath[1] = asset();

        treasuryFeePercentage = 1000;
        minToSwap = 1e15;
        slippagePercentage = 500;

        IERC20Upgradeable(asset()).approve(address(lsdStakingYieldPool), type(uint256).max);
        IERC20Upgradeable(wETH).approve(address(camelotDex), type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 earned = lsdStakingYieldPool.earned(address(this)) + IERC20Upgradeable(wETH).balanceOf(address(this));
        uint256 rewardEarned = 0;

        if (earned > minToSwap) {
            uint256[] memory rewards = camelotDex.getAmountsOut(earned, swapPath);
            if (treasury == address(0)) {
                rewardEarned = rewards[1];
            } else {
                rewardEarned = rewards[1] * (HUNDRED_PERCENT - treasuryFeePercentage) / HUNDRED_PERCENT;
            }
        }

        return lsdStakingYieldPool.balanceOf(address(this)) + IERC20Upgradeable(asset()).balanceOf(address(this))
            + rewardEarned;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        require(assets > 0, "UpgradeableVault: withdraw assets must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: withdraw to the zero address");

        _depositAssets();
        require(assets <= lsdStakingYieldPool.balanceOf(address(this)), "UpgradeableVault: withdraw more than balance");

        uint256 assetsBeforeWithdraw = IERC20Upgradeable(asset()).balanceOf(address(this));
        _withdrawAssets(assets);
        uint256 assetsWithdrawn = IERC20Upgradeable(asset()).balanceOf(address(this)) - assetsBeforeWithdraw;
        uint256 shares = ERC4626Upgradeable.withdraw(assetsWithdrawn, receiver, owner);

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        require(shares > 0, "UpgradeableVault: redeem shares must be greater than 0");
        require(receiver != address(0), "UpgradeableVault: redeem to the zero address");
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        _depositAssets();
        uint256 requiredAssets = previewRedeem(shares);
        require(
            requiredAssets <= lsdStakingYieldPool.balanceOf(address(this)), "UpgradeableVault: redeem more than balance"
        );

        uint256 assetsBeforeWithdraw = IERC20Upgradeable(asset()).balanceOf(address(this));
        _withdrawAssets(requiredAssets);
        uint256 assetsWithdrawn = IERC20Upgradeable(asset()).balanceOf(address(this)) - assetsBeforeWithdraw;
        _withdraw(_msgSender(), receiver, owner, assetsWithdrawn, shares);

        return requiredAssets;
    }

    function _depositAssets() internal override {
        uint256 totalToDeposit = IERC20Upgradeable(asset()).balanceOf(address(this));

        if (totalToDeposit > 0) {
            lsdStakingYieldPool.stake(totalToDeposit);
        }
    }

    function _withdrawAssets(uint256 amount) internal override {
        lsdStakingYieldPool.withdraw(amount);
    }

    function _collectRewards() internal override {
        uint256 balanceBefore = IERC20Upgradeable(wETH).balanceOf(address(this));
        lsdStakingYieldPool.getReward();

        if (treasury != address(0)) {
            uint256 balanceAfter = IERC20Upgradeable(wETH).balanceOf(address(this));
            uint256 reward = balanceAfter - balanceBefore;
            uint256 fee = reward * treasuryFeePercentage / HUNDRED_PERCENT;
            if (fee > 0) {
                IERC20Upgradeable(wETH).transfer(treasury, fee);
            }
        }

        uint256 totalRewards = IERC20Upgradeable(wETH).balanceOf(address(this));

        if (totalRewards > minToSwap) {
            uint256[] memory amountsOut = camelotDex.getAmountsOut(totalRewards, swapPath);
            uint256 minAmountOut = amountsOut[1] * (HUNDRED_PERCENT - slippagePercentage) / HUNDRED_PERCENT;

            camelotDex.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                totalRewards, minAmountOut, swapPath, address(this), address(0), block.timestamp
            );
        }
    }

    function _validateRecoverableToken(address token) internal view override {
        require(token != wETH, "Cannot recover wETH");
        require(token != address(asset()), "Cannot recover Acid");
    }
}

