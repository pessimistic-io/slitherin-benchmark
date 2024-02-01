// SPDX-License-Identifier: MIT

/// @title Arbitrary Frequencies
/// @author transientlabs.xyz

pragma solidity 0.8.14;

import "./ERC721TLCreator.sol";

contract ArbitraryFrequencies is ERC721TLCreator {

    /**
    *   @param royaltyRecipient is the royalty recipient
    *   @param royaltyPercentage is the royalty percentage to set
    *   @param admin is the admin address
    */
    constructor (
        address royaltyRecipient,
        uint256 royaltyPercentage,
        address admin
    )
    ERC721TLCreator("Arbitrary Frequencies", "MOVE", royaltyRecipient, royaltyPercentage, admin)
    {}
}
