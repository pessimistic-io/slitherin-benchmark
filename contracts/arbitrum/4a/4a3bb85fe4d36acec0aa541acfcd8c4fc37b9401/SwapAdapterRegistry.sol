// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AccessControl } from "./AccessControl.sol";
import { Constants } from "./Constants.sol";

contract SwapAdapterRegistry is AccessControl {
    // Mapping (hash of SwapAdapter name => SwapAdapter address).
    // Note that if the result is address(0) then there is no swap adapter registered with that hash.
    // The purpose of this is to force keepers to work only with endorsed swap modules, which helps minimize necessary trust in keepers.
    mapping(bytes32 => address) public swapAdapters;

    /**
     * @dev function to allow governance to add new swap adapters.
     * Note that this function is also capable of editing existing swap adapter addresses.
     * @param _swapAdapterHash is the hash of the swap adapter name, i.e. keccak256("UniswapSwapAdapter")
     * @param _swapAdapterAddress is the address of the swap adapter contract.
     */
    function registerSwapAdapter(
        bytes32 _swapAdapterHash,
        address _swapAdapterAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        swapAdapters[_swapAdapterHash] = _swapAdapterAddress;
    }
}

