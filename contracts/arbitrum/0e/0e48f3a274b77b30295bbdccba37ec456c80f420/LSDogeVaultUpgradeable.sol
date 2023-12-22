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

        if (earned > 0) {
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
        _addRatePoint();

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
            uint256 minAmountOut =
                twap() * (HUNDRED_PERCENT - slippagePercentage) * totalRewards / minToSwap / HUNDRED_PERCENT;

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

