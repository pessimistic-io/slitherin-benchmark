// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.4;

import "./Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;
    address private _contractManager;

    event ContractManagerTransferred(
        address indexed previousContractManager,
        address indexed newContractManager
    );

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferContractManager(msg.sender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), 'Ownable: caller is not the owner');
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            'Ownable: new owner is the zero address'
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev Returns the manager of the contract
     */
    function contractManager() public view virtual returns (address) {
        return _contractManager;
    }

    /**
     * @dev Throws if called by any account other than the Contract Manager.
     */
    modifier onlyContractManager() {
        require(
            _msgSender() == _contractManager,
            'Ownable: caller is not the contract manager'
        );
        _;
    }

    /**
     * @dev Transfers manager of the contract to a new account (`newContractManager`).
     * Can only be called by the current _contractManager.
     */
    function transferContractManager(address newContractManager)
        public
        virtual
        onlyContractManager
    {
        require(
            newContractManager != address(0),
            'Ownable: new contract owner is the zero address'
        );
        _transferContractManager(newContractManager);
    }

    /**
     * @dev Transfers management of the contract to a new account (`newContractManager`).
     * Internal function without access restriction.
     */
    function _transferContractManager(address newContractManager)
        internal
        virtual
    {
        address oldContractManager = _contractManager;
        _contractManager = newContractManager;

        emit ContractManagerTransferred(oldContractManager, newContractManager);
    }
}

