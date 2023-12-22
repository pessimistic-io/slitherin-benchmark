// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./Ownable.sol";

contract DuelPepesWhitelist is Ownable {
    // Whitelisted addresses
    mapping (address => bool) public whitelistedAddresses;

    // Determine if whitelist is active
    bool public isWhitelistActive;

    /**
    * Adds a new duellor to the whitelist
    * @param duellor Address of duellor
    * @return Whether address was added
    */
    function addToAddressesWhitelist(address duellor)
    public
    onlyOwner
    returns (bool) {
      require(duellor != address(0), "Invalid address");

      whitelistedAddresses[duellor] = true;

      return true;
    }

    /**
    * Removes a duellor from the whitelist
    * @param duellor Address of challenger
    * @return Whether address was removed
    */
    function removeFromAddressesWhitelist(address duellor)
    public
    onlyOwner
    returns (bool) {
      require(duellor != address(0), "Invalid address");

      whitelistedAddresses[duellor] = false;

      return true;
    }

    /**
    * Check if duellor is whitelisted
    * @param duellor Address of duellor
    * @return Whether address was removed
    */
    function isWhitelisted(address duellor)
    public
    view
    returns (bool) {
      return whitelistedAddresses[duellor];
    }

    /**
    * Update isWhitelistActive
    * @param status True or false
    */
    function setWhitelistStatus(bool status)
    public
    onlyOwner {
      isWhitelistActive = status;
    }
}
