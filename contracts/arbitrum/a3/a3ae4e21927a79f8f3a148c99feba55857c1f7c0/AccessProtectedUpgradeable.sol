// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";

abstract contract AccessProtectedUpgradeable is OwnableUpgradeable {
    mapping(address => bool) public isAdmin; // user address => admin? mapping

    event AdminAccessSet(address _admin, bool _enabled);

    function __AccessProtected_init() internal onlyInitializing {
        __AccessProtected_init_unchained();
        __Ownable_init();
    }

    function __AccessProtected_init_unchained() internal onlyInitializing {
        isAdmin[_msgSender()] = true;
    }

    /**
     * Throws if called by any account other than the Admin.
     */
    modifier onlyAdmin() {
        require(isAdmin[_msgSender()] || _msgSender() == owner(), "AccessProtected: caller is not an admin");
        _;
    }

    /**
     * @notice Set Admin Access
     *
     * @param admin - Address of Minter
     * @param enabled - Enable/Disable Admin Access
     */
    function setAdmin(address admin, bool enabled) public onlyOwner {
        isAdmin[admin] = enabled;
        emit AdminAccessSet(admin, enabled);
    }
}

