// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./Address.sol";
import "./IInitializable.sol";
import "./Storage.sol";

/**
 * @title Initializable
 * @notice Library to manage the initialization lifecycle of upgradeable contracts
 * @dev `Initializable.sol` allows the creation of pseudo-constructors for upgradeable contracts. One
 *      `initializer` should be declared per top-level contract. Child contracts can use the `onlyInitializer`
 *      modifier to tag their internal initialization functions to ensure that they can only be called
 *      from a top-level `initializer` or a constructor.
 */
abstract contract Initializable is IInitializable {
    /// @dev The initialized flag
    Uint256Storage private constant _version = Uint256Storage.wrap(keccak256("equilibria.root.Initializable.version"));

    /// @dev The initializing flag
    BoolStorage private constant _initializing = BoolStorage.wrap(keccak256("equilibria.root.Initializable.initializing"));

    /// @dev Can only be called once per version, `version` is 1-indexed
    modifier initializer(uint256 version) {
        if (version == 0) revert InitializableZeroVersionError();
        if (_version.read() >= version) revert InitializableAlreadyInitializedError(version);

        _version.store(version);
        _initializing.store(true);

        _;

        _initializing.store(false);
        emit Initialized(version);
    }

    /// @dev Can only be called from an initializer or constructor
    modifier onlyInitializer() {
        if (!_constructing() && !_initializing.read()) revert InitializableNotInitializingError();
        _;
    }

    /**
     * @notice Returns whether the contract is currently being constructed
     * @dev {Address.isContract} returns false for contracts currently in the process of being constructed
     * @return Whether the contract is currently being constructed
     */
    function _constructing() private view returns (bool) {
        return !Address.isContract(address(this));
    }
}

