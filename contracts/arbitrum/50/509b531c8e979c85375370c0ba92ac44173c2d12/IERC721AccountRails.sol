// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @notice using the consistent Access layer, expose external functions for interacting with core logic
interface IERC721AccountRails {
    error ImplementationNotApproved(address implementation);

    /// @dev Initialize the ERC721AccountRails contract with the initialization data.
    /// @param initData Additional initialization data if required by the contract.
    function initialize(bytes calldata initData) external;
}

