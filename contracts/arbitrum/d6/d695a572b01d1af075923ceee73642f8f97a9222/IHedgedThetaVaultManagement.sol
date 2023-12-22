// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IRewardRouter.sol";

interface IHedgedThetaVaultManagement {

	event FulfillerSet(address newFulfiller);
	event HedgeAdjusterSet(address newHedgeAdjuster);
	event RewardRouterSet(address rewardRouter, address thetaRewardTracker);
	event DepositHoldingsPercentageSet(uint32 newHoldingsPercentage);
	event WithdrawFeePercentageSet(uint32 newWithdarwFeePercentage);

    function adjustHedge(bool withdrawFromVault) external;

    function setFulfiller(address newFulfiller) external;
    function setHedgeAdjuster(address newHedgeAdjuster) external;
    function setRewardRouter(IRewardRouter rewardRouter, address thetaRewardTracker) external;

    function setDepositHoldingsPercentage(uint32 newHoldingsPercentage) external;
    function setWithdrawFeePercentage(uint32 newWithdarwFeePercentage) external;
}

