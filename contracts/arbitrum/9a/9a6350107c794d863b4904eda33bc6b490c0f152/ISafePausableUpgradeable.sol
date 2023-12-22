// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IAccessControlEnumerableUpgradeable.sol";

import "./IPendingOwnableUpgradeable.sol";

interface ISafePausableUpgradeable is
    IAccessControlEnumerableUpgradeable,
    IPendingOwnableUpgradeable
{
    function PAUSER_ROLE() external pure returns (bytes32);

    function UNPAUSER_ROLE() external pure returns (bytes32);

    function PAUSER_ADMIN_ROLE() external pure returns (bytes32);

    function UNPAUSER_ADMIN_ROLE() external pure returns (bytes32);

    function pause() external;

    function unpause() external;
}

