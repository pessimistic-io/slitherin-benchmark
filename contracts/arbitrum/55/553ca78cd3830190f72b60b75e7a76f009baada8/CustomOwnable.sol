// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/**
 * @title Represents an ownable resource.
 */
contract CustomOwnable {
    // The current owner of this resource.
    address internal _owner;

    /**
     * @notice This event is triggered when the current owner transfers ownership of the contract.
     * @param previousOwner The previous owner
     * @param newOwner The new owner
     */
    event OnOwnershipTransferred (address previousOwner, address newOwner);

    /**
     * @notice This modifier indicates that the function can only be called by the owner.
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == msg.sender, "Only owner");
        _;
    }

    /**
     * @notice Transfers ownership to the address specified.
     * @param addr Specifies the address of the new owner.
     * @dev Throws if called by any account other than the owner.
     */
    function transferOwnership (address addr) external virtual onlyOwner {
        require(addr != address(0), "non-zero address required");
        _transferOwnership(addr);
    }

    /**
     * @notice Gets the owner of this contract.
     * @return Returns the address of the owner.
     */
    function owner () external virtual view returns (address) {
        return _owner;
    }

    function _transferOwnership (address addr) internal virtual {
        address oldValue = _owner;
        _owner = addr;
        emit OnOwnershipTransferred(oldValue, _owner);
    }
}
