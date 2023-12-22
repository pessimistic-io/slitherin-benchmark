// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.18;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract BarqAwardsV0 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public reinitializer(1) {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {
        // This method's sole purpose is to revert when the caller is
        // unauthorized to make an upgrade. This is achieved by the `onlyOwner'
        // modifier above, hence no implementation.
    }
}

