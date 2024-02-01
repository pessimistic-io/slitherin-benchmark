// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/// @notice Simple contract ownership module
/// @author Solarbots (https://solarbots.io)
abstract contract Owned {
    address public owner;

    event OwnershipTransfer(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "NOT_OWNER");

        _;
    }

    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransfer(address(0), _owner);
    }

    function setOwner(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "INVALID_OWNER");

        owner = newOwner;

        emit OwnershipTransfer(msg.sender, newOwner);
    }
}

