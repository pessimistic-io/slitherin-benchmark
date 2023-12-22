// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./CommonDependencies.sol";

interface IPriorityPoolFactory {
    function poolCounter() external view returns (uint256);

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

    function poolRegistered(address) external view returns (bool);

    function dynamic(address) external view returns (bool);
}

interface IPriorityPool {
    function setCoverIndex(uint256 _newIndex) external;

    function minAssetRequirement() external view returns (uint256);

    function activeCovered() external view returns (uint256);
}

abstract contract ProtectionPoolDependencies {
    address public priorityPoolFactory;
    address public policyCenter;
    address public incidentReport;
}

