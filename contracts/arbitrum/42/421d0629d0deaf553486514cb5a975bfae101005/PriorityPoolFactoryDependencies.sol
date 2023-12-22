// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IPolicyCenter {
    function storePoolInformation(
        address _pool,
        address _token,
        uint256 _poolId
    ) external;
}

interface IWeightedFarmingPool {
    function addPool(address _token) external;

    function addToken(
        uint256 _id,
        address _token,
        uint256 _weight
    ) external;

    function updateRewardSpeed(
        uint256 _id,
        uint256 _newSpeed,
        uint256[] memory _years,
        uint256[] memory _months
    ) external;

    function updateWeight(
        uint256 _id,
        address _token,
        uint256 _newWeight
    ) external;
}

interface IProtectionPool {
    function getTotalActiveCovered() external view returns (uint256);

    function getLatestPrice() external returns (uint256);

    function removedLiquidity(uint256 _amount, address _provider)
        external
        returns (uint256);

    function removedLiquidityWhenClaimed(uint256 _amount, address _to) external;

    function pauseProtectionPool(bool _paused) external;

    function stakedSupply() external view returns (uint256);
}

interface IPriorityPoolDeployer {
    function deployPool(
        uint256 poolId,
        string calldata _name,
        address _protocolToken,
        uint256 _maxCapacity,
        uint256 _basePremiumRatio
    ) external returns (address);

    function getPoolAddress(
        uint256 poolId,
        string calldata _name,
        address _protocolToken,
        uint256 _maxCapacity,
        uint256 _basePremiumRatio
    ) external view returns (address);
}

abstract contract PriorityPoolFactoryDependencies {
    // Priority Pools need access to executor address
    address public executor;
    address public policyCenter;
    address public protectionPool;
    address public incidentReport;
    address public weightedFarmingPool;

    address public priorityPoolDeployer;
}

