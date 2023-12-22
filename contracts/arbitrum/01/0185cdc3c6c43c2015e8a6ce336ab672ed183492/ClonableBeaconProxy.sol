// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./BeaconProxy.sol";

/// @title  Clonable beacon proxy
/// @notice Used for upgrading PlennyERC20
/// @dev    Uses a beacon proxy standard to upgrade the PlennyERC20 through PlennyDistribution
contract ClonableBeaconProxy is BeaconProxy {
    /* solhint-disable-next-line no-empty-blocks */
    /// @notice Extends BeaconProxy
    /// @dev    Uses sender as a beacon address
    constructor() public BeaconProxy(msg.sender, "") {}
}

