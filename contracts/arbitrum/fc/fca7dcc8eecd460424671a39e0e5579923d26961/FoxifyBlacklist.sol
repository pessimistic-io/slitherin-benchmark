// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./IFoxifyBlacklist.sol";

/**
 * @title FoxifyBlacklist
 * @notice Contract for managing a blacklist of addresses in the Foxify project.
 * @notice This contract uses the EnumerableSet library from OpenZeppelin to manage a set of blacklisted addresses.
 * @notice Only the contract owner can add or remove addresses from the blacklist.
 */
contract FoxifyBlacklist is Ownable, IFoxifyBlacklist {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _blacklist;

    /**
     * @notice Returns the address at the specified index in the blacklist.
     * @param index The index of the address to return.
     * @return The address at the specified index in the blacklist.
     */
    function blacklist(uint256 index) external view returns (address) {
        return _blacklist.at(index);
    }

    /**
     * @notice Returns the number of addresses in the blacklist.
     * @return The number of addresses in the blacklist.
     */
    function blacklistCount() external view returns (uint256) {
        return _blacklist.length();
    }

    /**
     * @notice Returns true if the specified address is in the blacklist.
     * @param wallet The address to check.
     * @return True if the specified address is in the blacklist, false otherwise.
     */
    function blacklistContains(address wallet) external view returns (bool) {
        return _blacklist.contains(wallet);
    }

    /**
     * @notice Returns an array of up to  limit  addresses starting at index  offset  in the blacklist.
     * @param offset The starting index of the addresses to return.
     * @param limit The maximum number of addresses to return.
     * @return output An array of up to  limit  addresses starting at index  offset  in the blacklist.
     */
    function blacklistList(uint256 offset, uint256 limit) external view returns (address[] memory output) {
        uint256 blacklistLength = _blacklist.length();
        if (offset >= blacklistLength) return new address[](0);
        uint256 to = offset + limit;
        if (blacklistLength < to) to = blacklistLength;
        output = new address[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _blacklist.at(offset + i);
    }

    /**
     * @notice Adds the specified addresses to the blacklist.
     * @param wallets An array of addresses to add to the blacklist.
     * @return True if the operation was successful, false otherwise.
     */
    function blacklistWallets(address[] memory wallets) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < wallets.length; i++) {
            _blacklist.add(wallets[i]);
        }
        emit Blacklisted(wallets);
        return true;
    }

    /**
     * @notice Removes the specified addresses from the blacklist.
     * @param wallets An array of addresses to remove from the blacklist.
     * @return True if the operation was successful, false otherwise.
     */
    function unblacklistWallets(address[] memory wallets) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < wallets.length; i++) {
            _blacklist.remove(wallets[i]);
        }
        emit Unblacklisted(wallets);
        return true;
    }
}

