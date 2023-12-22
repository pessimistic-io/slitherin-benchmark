// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import "./Ownable.sol";
import "./Address.sol";
import "./IBeaconInterface.sol";

contract Beacon is IBeaconInterface, Ownable {
    // Storage

    /// @dev Current implementation address for this beacon,
    ///      i.e. the address which all beacon proxies will delegatecall to.
    address public implementation;

    // Constructor

    /// @param implementationAddress The address all beaconProxies will delegatecall to.
    constructor(address implementationAddress) {
        _setImplementationAddress(implementationAddress);
    }

    /// @dev Upgrades the implementation address of the beacon or the address that the beacon points to.
    /// @param newImplementation Address of implementation that the beacon should be upgraded to.
    function upgradeImplementationTo(address newImplementation)
        public
        virtual
        onlyOwner
    {
        _setImplementationAddress(newImplementation);
    }

    function _setImplementationAddress(address newImplementation) internal {
        require(
            Address.isContract(newImplementation),
            "UpgradeableBeacon: implementation is not a contract"
        );
        implementation = newImplementation;
        emit Upgraded(newImplementation);
    }
}

