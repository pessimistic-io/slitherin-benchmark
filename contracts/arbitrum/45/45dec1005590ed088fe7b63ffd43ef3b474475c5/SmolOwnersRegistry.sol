// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./EnumerableSetUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

import "./ICreatureOwnerResolver.sol";

/**
 * @title  SmolOwnersRegistry contract
 * @author Archethect
 * @notice This contract contains all functionalities for verifying Smol ownership
 */
contract SmolOwnersRegistry is Initializable, OwnableUpgradeable, ICreatureOwnerResolver {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    ICreatureOwnerResolver public root;
    EnumerableSetUpgradeable.AddressSet private _resolvers;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(ICreatureOwnerResolver root_) public initializer {
        __Ownable_init();
        setRoot(root_);
    }

    function setRoot(ICreatureOwnerResolver root_) public onlyOwner {
        require(address(root_) != address(0), "SMOLOWNERSREGISTRY:ILLEGAL_ADDRESS");
        root = root_;
    }

    function addResolver(address resolver) external onlyOwner {
        _resolvers.add(resolver);
    }

    function removeResolver(address resolver) external onlyOwner {
        _resolvers.remove(resolver);
    }

    function isOwner(address account, uint256 tokenId) external view override returns (bool) {
        if (root.isOwner(account, tokenId)) {
            return true;
        }
        return _isOwner(account, tokenId);
    }

    function _isOwner(address account, uint256 tokenId) internal view returns (bool) {
        for (uint256 i = 0; i < EnumerableSetUpgradeable.length(_resolvers); i++) {
            if (ICreatureOwnerResolver(_resolvers.at(i)).isOwner(account, tokenId)) {
                return true;
            }
        }
        return false;
    }

    function isResolver(address resolver) external view returns (bool) {
        return _resolvers.contains(resolver);
    }
}

