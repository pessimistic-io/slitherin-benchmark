// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract NumaStore
{
    struct NumaStorage
    {
        uint sellFeeBips;
        mapping (address => bool) isIncludedInFees;
        mapping (address => bool) wlSpenders;
    }

    bytes32 private constant STORAGE_SLOT = keccak256("numa.erc20.storage");

    // Creates and returns the storage pointer to the struct.
    function numaStorage() internal pure returns(NumaStorage storage ns) 
    {
       bytes32 position = STORAGE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ns.slot := position
        }
    }

}
