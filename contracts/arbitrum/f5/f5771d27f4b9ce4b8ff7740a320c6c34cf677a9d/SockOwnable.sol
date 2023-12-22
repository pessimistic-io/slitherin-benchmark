// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./Context.sol";

/* solhint-disable private-variables */

/**
 * @title SockOwnable Contract
 * @dev Provides access control mechanisms with three types of owners - 'owner' and 'sockOwner' and 'recoveryOwner'.
 * The 'owner' and 'sockOwner' can have distinct rights and the distinction allows functions to
 * be restricted to either of them or both.
 * The 'recoveryOwner' only has permissions to change the 'owner'.
 * @notice SockOwnable is only intended to be inherited by SockAccount do not use with other contracts.
 */
abstract contract SockOwnable is Context {
    address internal _sockOwner;
    address internal _owner;
    address internal _recoveryOwner;

    event SockOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RecoveryOwnershipTransferred(address indexed previousRecoveryOwner, address indexed newRecoveryOwner);

    /**
     * @dev Ensures only the 'owner' can call the function.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Ensures either 'owner' or 'sockOwner' can call the function.
     */
    modifier onlyOwnerOrSockOwner() {
        require(
            _msgSender() == owner() ||
            _msgSender() == sockOwner(),
            "caller is not the owner or sock owner");
        _;
    }

    /**
     * @dev Ensures only the 'recoveryOwner' can call the function if recovery is enabled.
     * Otherwise, the 'owner' can call the function.
     */
    modifier onlyRecoveryOwners() {
        _checkRecoverability();
        _;
    }

    constructor () {
        _sockOwner = _msgSender();
        _owner = _msgSender();
        emit SockOwnershipTransferred(address(0), _sockOwner);
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @notice Allows transferring the 'owner' rights to another address.
     * @param newOwner The address to transfer the 'owner' rights to.
     */
    function transferOwnership(address newOwner) external virtual onlyRecoveryOwners {
        _transferOwnership(newOwner);
    }

    /**
     * @notice Allows transferring the 'recoveryOwner' rights to another address.
     * @param newRecoveryOwner The address to transfer the 'recoveryOwner' rights to.
     */
    function transferRecoveryOwnership(address newRecoveryOwner) external virtual onlyRecoveryOwners {
        _transferRecoveryOwnership(newRecoveryOwner);
    }

    /**
     * @return The current 'sockOwner' of the contract.
     */
    function sockOwner() public view virtual returns (address) {
        return _sockOwner;
    }

    /**
     * @return The current 'owner' of the contract.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @return The current 'recoveryOwner' of the contract.
     */
    function recoveryOwner() public view virtual returns (address) {
        return _recoveryOwner;
    }

    /**
     * @dev Internal function to transfer 'sockOwner' rights to another address.
     * @param newOwner The address to transfer the 'sockOwner' rights to.
     */
    function _transferSockOwnership(address newOwner) internal virtual {
        address oldOwner = _sockOwner;
        _sockOwner = newOwner;
        emit SockOwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev Internal function to transfer 'owner' rights to another address.
     * @param newOwner The address to transfer the 'owner' rights to.
     */
    function _transferOwnership(address newOwner) internal virtual {
        require(newOwner != address(0), "new owner cannot be the zero address");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev Internal function enabling the recovery mechanism.
     * @param newRecoveryOwner The address to set as the 'newRecoveryOwner'.
     */
    function _transferRecoveryOwnership(address newRecoveryOwner) internal virtual {
        address oldRecoveryOwner = _recoveryOwner;
        _recoveryOwner = newRecoveryOwner;
        emit RecoveryOwnershipTransferred(oldRecoveryOwner, newRecoveryOwner);
    }

    /**
     * @dev Ensures that the caller is the 'owner'.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "caller is not the owner");
    }

    /**
     * @dev Ensures that the caller is the 'owner' or 'recoveryOwner'.
     */
    function _checkRecoverability() internal view {
        require(_msgSender() == recoveryOwner() || _msgSender() == owner(), "caller is not the recovery owner or owner");
    }
}

