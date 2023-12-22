// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.19;

import "./UpgradeableVault.sol";

import "./IVester.sol";
import "./IMintableToken.sol";

import "./console.sol";

contract LockedAcidVaultUpgradeable is UpgradeableVault {
    uint256 public feesToCollect;
    IVester private vester;
    uint256 public burnPercentage;
    uint256[50] private __gap;

    function initialize(
        address _asset,
        address _rewardTracker,
        address _stakingYieldPool,
        address _vester,
        address _wstETH,
        address _camelotDex,
        address _wETH,
        address _esAcid,
        RatePoint[] memory _initialRatePoints
    ) public initializer {
        __ERC4626_init(IERC20Upgradeable(_asset));
        __ERC20_init("Infinite Acid", "iACID");
        __Ownable_init();
        __UUPSUpgradeable_init();

        rewardTracker = IRewardTracker(_rewardTracker);
        stakingYieldPool = IStakingYieldPool(_stakingYieldPool);
        wstETH = _wstETH;
        wETH = _wETH;
        esAcid = _esAcid;
        camelotDex = ICamelotDex(_camelotDex);
        vester = IVester(_vester);

        for (uint256 i = 0; i < _initialRatePoints.length; i++) {
            ratePoints.push(_initialRatePoints[i]);
        }

        swapPath = new address[](2);
        swapPath[0] = asset();
        swapPath[1] = wETH;

        feesToCollect = 0;
        minToSwap = 1e5;
        treasuryFeePercentage = 1000;
        slippagePercentage = 500;
        burnPercentage = 1000;

        IERC20Upgradeable(asset()).approve(address(rewardTracker), type(uint256).max);
        IERC20Upgradeable(esAcid).approve(address(vester), type(uint256).max);
    }

    function setBurnPercentage(uint256 _burnPercentage) external onlyOwner {
        require(_burnPercentage <= HUNDRED_PERCENT, "Burn percentage too high");
        burnPercentage = _burnPercentage;
    }

    function maxWithdraw(address /*owner*/ ) public pure override returns (uint256) {
        return 0;
    }

    function maxRedeem(address /*owner*/ ) public pure override returns (uint256) {
        return 0;
    }

    function previewWithdraw(uint256 /*assets*/ ) public pure override returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256 /*shares*/ ) public pure override returns (uint256) {
        return 0;
    }

    function depositWithRewards(uint256 amount, address to) public pure override returns (uint256) {
        return 0;
    }

    function deposit(uint256 amount, address to) public pure override returns (uint256) {
        return 0;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 earned = (
            IERC20Upgradeable(address(vester)).balanceOf(address(this)) + rewardTracker.claimable(address(this))
                + IERC20Upgradeable(esAcid).balanceOf(address(this))
        ) * (HUNDRED_PERCENT - treasuryFeePercentage - burnPercentage) / HUNDRED_PERCENT;

        return IERC20Upgradeable(address(rewardTracker)).balanceOf(address(this))
            + IERC20Upgradeable(asset()).balanceOf(address(this)) + earned + vester.pairAmounts(address(this))
            - feesToCollect;
    }

    function _depositAssets() internal override {
        uint256 totalToDeposit = IERC20Upgradeable(asset()).balanceOf(address(this)) - feesToCollect;
        if (totalToDeposit > 0) {
            rewardTracker.deposit(totalToDeposit, block.timestamp + 365 days);
        }
    }

    function _collectRewards() internal override {
        _addRatePoint();

        rewardTracker.claim(0);
        uint256 reward = IERC20Upgradeable(esAcid).balanceOf(address(this));
        uint256 acidAmount = vester.claim();

        try vester.deposit(reward) {} catch {}

        if (acidAmount > 0) {
            feesToCollect += acidAmount * (treasuryFeePercentage + burnPercentage) / HUNDRED_PERCENT;

            if (treasury != address(0) && feesToCollect >= minToSwap) {
                IERC20Upgradeable(asset()).approve(address(camelotDex), feesToCollect);
                uint256 minAmountOut =
                    twap() * (HUNDRED_PERCENT - slippagePercentage) * feesToCollect / minToSwap / HUNDRED_PERCENT;

                camelotDex.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    feesToCollect, minAmountOut, swapPath, address(this), address(0), block.timestamp
                );

                feesToCollect = 0;
                uint256 fees = IERC20Upgradeable(wETH).balanceOf(address(this));
                IERC20Upgradeable(wETH).transfer(treasury, fees);
            }
        }
    }

    function _validateRecoverableToken(address token) internal view override {}
}

