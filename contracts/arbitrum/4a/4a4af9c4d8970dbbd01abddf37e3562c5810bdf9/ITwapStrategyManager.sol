//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

import "./ITwapStrategyFactory.sol";

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

interface ITwapStrategyManager {
    function isUserWhiteListed(address _account) external view returns (bool);

    function isAllowedToManage(address) external view returns (bool);

    function isAllowedToBurn(address) external view returns (bool);

    function managementFeeRate() external view returns (uint256); // 1e8 decimals

    function performanceFeeRate() external view returns (uint256); // 1e8 decimals

    function operator() external view returns (address);

    function limit() external view returns (uint256);

    function feeTo() external view returns (address);

    function factory() external view returns (ITwapStrategyFactory);

    function incrementSwapCounter() external;

    function twapPricePeriod() external view returns (uint256);

    function getRewardParameters() external view returns(IGaugeV2 _gauge, address _rewardReceiver, address[] memory _rewardTokens);
}

