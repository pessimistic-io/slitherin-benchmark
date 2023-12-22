// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISolidlyLpStrategy {
    function deposit() external;

    function withdraw(uint256 _amount) external;
    
    function withdrawAsLpTokens(uint256 _amount) external;

    function beforeDeposit() external;

    function harvest() external;

    function balanceOf() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function rewardsAvailable() external view returns (uint256);

    function setSpiritHarvest(bool _spiritHarvest) external;

    function setGaugeStaker(address _gaugeStaker) external;

    function setHarvestOnDeposit(bool _harvestOnDeposit) external;

    function setShouldGasThrottle(bool _shouldGasThrottle) external;

    function retireStrat() external;

    function panic() external;

    function pause() external;

    function unpause() external;

    function getRewardTokenToFeeTokenRoute() external view returns (address[] memory);

    function getRewardTokenToLp0TokenRoute() external view returns (address[] memory);

    function getRewardTokenToLp1TokenRoute() external view returns (address[] memory);

    function want() external view returns (address);

    function reward() external view returns (address);

    function lp0() external view returns (address);

    function lp1() external view returns (address);

    function input() external view returns (address);

    function depositLpTokens() external;
}

