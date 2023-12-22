// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IBinaryVault {
    function claimBettingRewards(
        address to,
        uint256 amount,
        bool isRefund
    ) external returns (uint256);

    function onRoundExecuted(uint256 wonAmount, uint256 loseAmount) external;

    function getMaxHourlyExposure() external view returns (uint256);

    function isFutureBettingAvailable() external view returns (bool);

    function onPlaceBet(
        uint256 amount,
        address from,
        uint256 endTime,
        uint8 position
    ) external;

    function getExposureAmountAt(uint256 endTime)
        external
        view
        returns (uint256 exposureAmount, uint8 direction);

    function whitelistMarkets(address) external view returns (bool, uint256);

    function updateExposureAmount() external;

    function getCurrentHourlyExposureAmount() external view returns (uint256);
}

