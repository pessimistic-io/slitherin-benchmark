// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUpgradeable {
    function upgradeTo(address implementation) external;
}
