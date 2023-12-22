// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IAccount.sol";
import "./IEntryPoint.sol";
import "./ERC721Holder.sol";
import "./ERC1155Holder.sol";

/// @dev This contract provides the basic logic for implementing the IAccount interface - validateUserOp
abstract contract Account is IAccount, ERC721Holder, ERC1155Holder {
    /// @dev This chain's EntryPoint contract address
    address public immutable entryPoint;

    /// @dev 8-Byte value signaling support for modular validation schema developed by GroupOS
    /// @notice To use, prepend signatures with a 32-byte word packed with 8-byte flag and target validator address,
    /// Leaving 4 empty bytes inbetween the packed values.
    /// Ie: `bytes32 validatorData == 0xf88284b100000000 | bytes32(uint256(uint160(address(callPermitValidator))));`
    bytes8 public constant VALIDATOR_FLAG = bytes8(bytes4(keccak256("VALIDATORFLAG"))) & 0xFFFFFFFF00000000;

    /// @param _entryPointAddress The contract address for this chain's ERC-4337 EntryPoint contract
    /// Official address for the most recent EntryPoint version is `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`
    constructor(address _entryPointAddress) {
        entryPoint = _entryPointAddress;
    }

    /// @dev View function to view the EntryPoint's deposit balance for this Account
    function getEntryPointBalance() public view returns (uint256) {
        return IEntryPoint(entryPoint).balanceOf(address(this));
    }

    /// @dev Function to pre-fund the EntryPoint contract's `depositTo()` function
    /// using payable call context + this contract's native currency balance
    function preFundEntryPoint() public payable virtual {
        // `address(this).balance` includes `msg.value`
        uint256 totalFunds = address(this).balance;
        IEntryPoint(entryPoint).depositTo{value: totalFunds}(address(this));
    }

    /// @dev Function to withdraw funds using the EntryPoint's `withdrawTo()` function
    /// @param recipient The address to receive from the EntryPoint balance
    /// @param amount The amount of funds to withdraw from the EntryPoint
    function withdrawFromEntryPoint(address payable recipient, uint256 amount) public virtual;
}

