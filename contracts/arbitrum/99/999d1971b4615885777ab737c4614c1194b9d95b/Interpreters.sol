/**
 * @notice
 * All of the interpreters for the ycVM.
 * This includes type-specific interpreters - i.e interpretDynamicVar(), etc.
 * 
 * Note that it may not include some interpreters and they will be included in the main contract.
 * This is because some of them depend on the core VM functionality
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./types.sol";
import "./Constants.sol";
import "./Utilities.sol";

contract Interpreters is YieldchainTypes, Constants, Utilities {
    /**
     * _parseDynamicVar
     * @param _arg - The dynamic-length argument to parse
     * @return the parsed arg. So the dynamic-length argument minus it's ABI-prepended 32 byte offset pointer
     */
    function _parseDynamicVar(
        bytes memory _arg
    ) public pure returns (bytes memory) {
        /**
         * We call the _removePrependedBytes() function with our arg,
         * and 32 as the amount of bytes to remove.
         * this will remove the first 32 bytes of our argument, which is supposed to be the
         * offset pointer to hence - and hence return a "parsed" version of it (just the length + data)
         */
        return _removePrependedBytes(_arg, 32);
    }
}

