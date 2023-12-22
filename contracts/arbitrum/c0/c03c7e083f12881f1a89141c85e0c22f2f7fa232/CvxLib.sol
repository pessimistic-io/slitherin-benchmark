pragma solidity >=0.8.0;
import "./IConvexWrapper.sol";
import "./IBentoBoxV1.sol";
import "./IERC20.sol";

interface ICvx {
    function claimable_reward(address token, address user) external view returns (uint256);
}

library CvxLib {
    IStrictERC20 constant crv = IStrictERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);

    function getClaimable(address cvxToken, address user) external view returns (uint256) {
        return ICvx(cvxToken).claimable_reward(address(crv), user);
    }

    function unstake(IBentoBoxV1 bentoBox, IERC20 collateral, address rewardRouter, uint256 collateralShare) external {
        uint256 amount = bentoBox.toAmount(collateral, collateralShare, false);
        bentoBox.deposit(collateral, address(this), address(this), 0, collateralShare);
    }

    function stake(IBentoBoxV1 bentoBox, IERC20 collateral, address rewardRouter, uint256 collateralShare) external {
        (uint256 amount, ) = bentoBox.withdraw(collateral, address(this), address(this), 0, collateralShare);
    }

    function harvest(
        address rewardRouter,
        address user,
        uint256 userCollateralShare,
        uint256 userRwardDebt,
        uint256 rewardPershare,
        uint256 totalCollateralShare
    ) external returns (uint256) {
        uint256 lastBalance = crv.balanceOf(address(this));
        IConvexWrapper(rewardRouter).getReward(address(this));
        uint256 tcs = totalCollateralShare;
        if (tcs > 0) {
            rewardPershare += ((crv.balanceOf(address(this)) - lastBalance) * 1e20) / tcs;
        }
        uint256 last = userRwardDebt;
        uint256 curr = (userCollateralShare * rewardPershare) / 1e20;

        if (curr > last) {
            crv.transfer(user, curr - last);
        }
        return rewardPershare;
    }
}

