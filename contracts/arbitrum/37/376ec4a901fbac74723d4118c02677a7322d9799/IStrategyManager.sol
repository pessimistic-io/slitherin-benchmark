//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

import "./IStrategyFactory.sol";

interface IGaugeV2 {
    function getRewardTokens() external view returns (address[] memory);
    function getReward(
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        address[] memory tokens,
        address receiver
    ) external;
}

interface IStrategyManager {
    function isUserWhiteListed(address _account) external view returns (bool);

    function isAllowedToManage(address) external view returns (bool);

    function isAllowedToBurn(address) external view returns (bool);

    function managementFeeRate() external view returns (uint256); // 1e8 decimals

    function performanceFeeRate() external view returns (uint256); // 1e8 decimals

    function operator() external view returns (address);

    function limit() external view returns (uint256);

    function allowedDeviation() external view returns (uint256); // 1e18 decimals

    function allowedSwapDeviation() external view returns (uint256); // 1e18 decimals

    function feeTo() external view returns (address);

    function factory() external view returns (IStrategyFactory);

    function increamentSwapCounter() external;

    function strategy() external view returns (address);

    function getRewardParameters() external view returns(IGaugeV2 _gauge, address _rewardReceiver, address[] memory _rewardTokens);
}

