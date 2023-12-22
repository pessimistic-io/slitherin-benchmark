// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IERC721.sol";

/*
 * Simple allowlist which checks if NFT collection is held by a user.
 * by @SteakHut Finance
 */
contract AllowList is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // NFT collection addresses to whitelist from paying deallocation fee
    EnumerableSet.AddressSet private whitelistedCollections;

    constructor() {}

    /**
     *
     */
    /**
     * EVENTS *****************
     */
    /**
     *
     */

    event WhitelistCollection(address collection);
    event RemoveCollection(address collection);

    /**
     *
     */
    /**
     * VIEW *****************
     */
    /**
     *
     */

    /// @notice Returns the type id at index `_index` where whitelist has a non-zero balance
    /// @param _index The position index
    /// @return The non-zero position at index `_index`
    function whitelistCollectionPositionAtIndex(uint256 _index) external view returns (address) {
        return whitelistedCollections.at(_index);
    }

    /// @notice Returns the number of whitelisted NFT collections
    /// @return The number of whitelisted NFT collections
    function whitelistCollectionPositionNumber() external view returns (uint256) {
        return whitelistedCollections.length();
    }

    /// @notice Returns if the user holds NFT collection
    /// @return isAllowListed true if user hold collection
    function isAllowlisted(address user) external view returns (bool isAllowListed) {
        for (uint256 i = 0; i < whitelistedCollections.length(); i++) {
            if (
                address(whitelistedCollections.at(i)) != address(0)
                    && IERC721(whitelistedCollections.at(i)).balanceOf(user) > 0 && user == tx.origin
            ) {
                isAllowListed = true;
            }
        }
    }

    /**
     *
     */
    /**
     * OWNER *****************
     */
    /**
     *
     */

    /**
     * @dev Adds a NFT collection to the whitelist
     */
    function addWhitelistedCollection(address collection) external onlyOwner {
        require(collection != address(0), "addWhitelistedCollection: Cannot whitelist 0 address");

        whitelistedCollections.add(collection);
        emit WhitelistCollection(collection);
    }

    /**
     * @dev removes a NFT collection from the whitelist
     */
    function removeWhitelistedCollection(address collection) external onlyOwner {
        require(collection != address(0), "removeWhitelistedCollection: Cannot remove whitelist of 0 address");

        whitelistedCollections.remove(collection);
        emit RemoveCollection(collection);
    }
}

