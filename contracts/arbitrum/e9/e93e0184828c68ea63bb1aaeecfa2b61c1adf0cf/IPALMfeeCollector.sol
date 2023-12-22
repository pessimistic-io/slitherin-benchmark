// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPALMfeeCollector {
    function collectManagementFees(address[] memory maturedVaults) external;

    function checker(address[] calldata allVaults)
        external
        view
        returns (bool canExec, bytes memory payload);

    function restoreOwnership(address palmManager_, address managerNewOwner_)
        external;
}

