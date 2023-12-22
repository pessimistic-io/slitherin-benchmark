// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IPriorityPoolFactory {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PoolCreated(
        address poolAddress,
        uint256 poolId,
        string protocolName,
        address protocolToken,
        uint256 maxCapacity,
        uint256 policyPricePerUSDC
    );

    struct PoolInfo {
        string a;
        address b;
        address c;
        uint256 d;
        uint256 e;
    }

    function deg() external view returns (address);

    function deployPool(
        string memory _name,
        address _protocolToken,
        uint256 _maxCapacity,
        uint256 _policyPricePerToken
    ) external returns (address);

    function executor() external view returns (address);

    function getPoolAddressList() external view returns (address[] memory);

    function getPoolInfo(uint256 _id) external view returns (PoolInfo memory);

    function incidentReport() external view returns (address);

    function priorityPoolFactory() external view returns (address);

    function maxCapacity() external view returns (uint256);

    function owner() external view returns (address);

    function policyCenter() external view returns (address);

    function poolCounter() external view returns (uint256);

    function poolInfoById(uint256)
        external
        view
        returns (
            string memory protocolName,
            address poolAddress,
            address protocolToken,
            uint256 maxCapacity,
            uint256 policyPricePerUSDC
        );

    function poolRegistered(address) external view returns (bool);

    function protectionPool() external view returns (address);

    function setProtectionPool(address _protectionPool) external;

    function updateMaxCapacity(bool _isUp, uint256 _maxCapacity) external;

    function tokenRegistered(address) external view returns (bool);

    function totalMaxCapacity() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function veDeg() external view returns (address);

    function updateDynamicPool(uint256 _poolId) external;

    function dynamicPoolCounter() external view returns (uint256);

    function dynamic(address _pool) external view returns (bool);

    function pools(uint256 _poolId)
        external
        view
        returns (
            string memory name,
            address poolAddress,
            address protocolToken,
            uint256 maxCapacity,
            uint256 basePremiumRatio
        );

    function payoutPool() external view returns (address);

    function pausePriorityPool(uint256 _poolId, bool _paused) external;

   
}

