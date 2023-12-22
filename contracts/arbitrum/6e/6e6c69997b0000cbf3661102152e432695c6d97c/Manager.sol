// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Ownable.sol";

abstract contract Manager is Ownable {
    address private _manager;

    event ManagerTransferred(address indexed previousManager, address indexed newManager);

    /**
     * @dev Initializes the contract setting the deployer as the initial manager.
     */
    constructor() {
        _transferManager(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the manager.
     */
    modifier onlyManagerAndOwner() {
        _checkManager();
        _;
    }

    /**
     * @dev Returns the address of the current manager.
     */
    function manager() public view virtual returns (address) {
        return _manager;
    }

    /**
     * @dev Throws if the sender is not the manager.
     */
    function _checkManager() internal view virtual {
        require(owner() == _msgSender()
            || manager() == _msgSender(), "Manageable: caller is not the manager or owner");
    }

    /**
     * @dev Transfers manager of the contract to a new account (`newManager`).
     * Can only be called by the current manager.
     */
    function transferManager(address newManager) public virtual onlyOwner {
        require(newManager != address(0), "Ownable: new manager is the zero address");
        _transferManager(newManager);
    }

    /**
     * @dev Transfers managership of the contract to a new account (`newmanager`).
     * Internal function without access restriction.
     */
    function _transferManager(address newManager) internal virtual {
        address oldManager = _manager;
        _manager = newManager;
        emit ManagerTransferred(oldManager, newManager);
    }
}

