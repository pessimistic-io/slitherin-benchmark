// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {AuthUpgradeable, Authority} from "./AuthUpgradeable.sol";

import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

/// @notice Upgradeability standard.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/Upgradeable.sol)
abstract contract Upgradeable is UUPSUpgradeable, AuthUpgradeable, PausableUpgradeable {
    error Upgradeable__NotOwner(address account);

    // slither-disable-next-line naming-convention
    function __Upgradeable_init(address _owner, Authority _authority) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Auth_init(_owner, _authority);
        __Pausable_init();
        __Upgradeable_init_unchained();
    }

    // slither-disable-next-line naming-convention no-empty-blocks
    function __Upgradeable_init_unchained() internal onlyInitializing {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Upgradeable__NotOwner(msg.sender);
        _;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function name() external view virtual returns (string memory);

    function version() external view virtual returns (string memory) {
        return '0.1.0';
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    // slither-disable-next-line naming-convention,unused-state
    uint256[50] private __gap;
}

