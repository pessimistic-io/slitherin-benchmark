// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICore {
    function isGovernor(address _address) external view returns (bool);

    function isGuardian(address _address) external view returns (bool);

    function isMultistrategy(address _address) external view returns (bool);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function createRole(bytes32 role, bytes32 adminRole) external;

    function grantGovernor(address governor) external;

    function grantGuardian(address guardian) external;

    function grantMultistrategy(address multistrategy) external;

    function grantRole(bytes32 role, address account) external;
}

