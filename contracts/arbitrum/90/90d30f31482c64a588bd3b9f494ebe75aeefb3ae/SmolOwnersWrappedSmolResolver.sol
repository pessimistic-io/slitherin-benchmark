// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./IERC721.sol";
import "./Initializable.sol";

import "./ICreatureOwnerResolver.sol";

/**
 * @title  SmolOwnersWrappedSmolResolver contract
 * @author Archethect
 * @notice This contract contains all functionalities for verifying Smol ownership of Wrapped Smols
 */
contract SmolOwnersWrappedSmolResolver is Initializable, ICreatureOwnerResolver {
    IERC721 public wrappedSmols;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address wrappedSmols_) public initializer {
        require(address(wrappedSmols_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        wrappedSmols = IERC721(wrappedSmols_);
    }

    function isOwner(address account, uint256 tokenId) external view override returns (bool) {
        try wrappedSmols.ownerOf(tokenId) returns (address result) {
            return account == result;
        } catch (bytes memory) {
            return false;
        }
    }
}

