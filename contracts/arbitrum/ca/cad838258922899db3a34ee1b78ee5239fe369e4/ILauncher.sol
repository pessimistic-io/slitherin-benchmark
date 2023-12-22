// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface ILauncher {
    event AcceptedShare2Earn(
        address from,
        address to,
        uint256 amount,
        uint256 reward
    );

    event BuyMFC(address to, uint256 amount, uint256 price);
    event EarnMFC(address to, uint256 amount);

    struct UserEarn {
        uint256 tgId;
        address user;
        uint256 earnTotal;
    }

    function launchDone() external view returns (bool);

    function getShare2MultiplyAmount(
        address shareId
    ) external view returns (uint256);

    function subShare2MultiplyAmount(
        address from,
        address to,
        uint256 amount,
        uint256 rewardAmoumt
    ) external;

    function getRemainSharePoolAmount() external view returns (uint256);

    function getTribeShare2MultiplyRemainTimes(
        address shareId
    ) external view returns (uint256);

    function computeShare2EarnReward(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint256);

    function getMaxHoldeAmount() external view returns (uint256);

    function isAuthorized(address shareId) external view returns (bool);

    function isBlackList(address account) external view returns (bool);
}

