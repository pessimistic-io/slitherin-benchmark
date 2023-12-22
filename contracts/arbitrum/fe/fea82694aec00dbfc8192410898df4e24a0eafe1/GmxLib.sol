pragma solidity >=0.8.0;
import "./IGmxRewardRouterV2.sol";
import "./IBentoBoxV1.sol";
import "./IGmxRewardTracker.sol";

library GmxLib {
    function getTrackers(address rewardRouter, bool isGlp) external view returns (address stakedTracker, address feeTracker) {
        if (!isGlp) return (IGmxRewardRouterV2(rewardRouter).stakedGmxTracker(), IGmxRewardRouterV2(rewardRouter).feeGmxTracker());
        return (IGmxRewardRouterV2(rewardRouter).stakedGlpTracker(), IGmxRewardRouterV2(rewardRouter).feeGlpTracker());
    }

    function getClaimable(address feeTracker, address user) external view returns (uint256) {
        return IGmxRewardTracker(feeTracker).claimable(user);
    }

    function unstake(IBentoBoxV1 bentoBox, IERC20 collateral, address rewardRouter, uint256 collateralShare, bool isGLP) external {
        uint256 amount = bentoBox.toAmount(collateral, collateralShare, false);
        if (!isGLP) {
            IGmxRewardRouterV2(rewardRouter).unstakeGmx(amount);
        }
        bentoBox.deposit(collateral, address(this), address(this), 0, collateralShare);
    }

    function stake(IBentoBoxV1 bentoBox, IERC20 collateral, address rewardRouter, uint256 collateralShare, bool isGLP) external {
        (uint256 amount, ) = bentoBox.withdraw(collateral, address(this), address(this), 0, collateralShare);
        if (!isGLP) {
            IGmxRewardRouterV2(rewardRouter).stakeGmx(amount);
        }
    }

    function harvest(
        address rewardRouter,
        address user,
        uint256 userCollateralShare,
        uint256 userRwardDebt,
        uint256 rewardPershare,
        uint256 totalCollateralShare
    ) external returns (uint256) {
        uint256 lastBalance = address(this).balance;
        IGmxRewardRouterV2(rewardRouter).handleRewards({
            shouldClaimGmx: true,
            shouldStakeGmx: true,
            shouldClaimEsGmx: true,
            shouldStakeEsGmx: true,
            shouldStakeMultiplierPoints: true,
            shouldClaimWeth: true,
            shouldConvertWethToEth: true
        });
        uint256 tcs = totalCollateralShare;
        if (tcs > 0) {
            rewardPershare += ((address(this).balance - lastBalance) * 1e20) / tcs;
        }
        uint256 last = userRwardDebt;
        uint256 curr = (userCollateralShare * rewardPershare) / 1e20;

        if (curr > last) {
            payable(user).call{value: curr - last, gas: 21000}("");
        }
        return rewardPershare;
    }
}

