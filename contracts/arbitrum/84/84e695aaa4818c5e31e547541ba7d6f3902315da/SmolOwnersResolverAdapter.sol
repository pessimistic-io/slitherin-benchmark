// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./IERC721.sol";
import "./Initializable.sol";

import "./ICreatureOwnerResolver.sol";

/**
 * @title  SmolOwnersResolverAdapter contract
 * @author Archethect
 * @notice This contract contains all functionalities for verifying Smol ownership
 */
contract SmolOwnersResolverAdapter is Initializable, ICreatureOwnerResolver {
    IERC721 public smolBrains;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address smolBrains_) public initializer {
        require(address(smolBrains_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        smolBrains = IERC721(smolBrains_);
    }

    function isOwner(address account, uint256 tokenId) external view override returns (bool) {
        return smolBrains.ownerOf(tokenId) == account;
    }
}

