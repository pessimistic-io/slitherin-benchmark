// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

interface IBeaconInterface {
    /// @dev Event emitted when the address that the beacon is pointing to is upgraded.
    /// @return address of the new implementation.
    event Upgraded(address indexed newImplementation);

    function implementation() external view returns (address);

    function upgradeImplementationTo(address newImplementation) external;
}

