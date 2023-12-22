// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./NPM.sol";
import "./IStore.sol";

/**
 * @title Proof of Authority Tokens (POTs)
 *
 * @dev POTs can't be used outside of the protocol
 * for example in DEXes. Once NPM token is launched, it will replace POTs.
 *
 * For now, Neptune Mutual team and a few others will have access to POTs.
 *
 * POTs aren't conventional ERC-20 tokens; they can't be transferred freely;
 * they don't have any value, and therefore must not be purchased or sold.
 *
 * Again, POTs are distributed to individuals and companies
 * who particpate in our governance and dispute management portals.
 *
 */
contract POT is NPM {
  IStore public s;
  mapping(address => bool) public whitelist;
  bytes32 public constant NS_MEMBERS = "ns:members";

  event WhitelistUpdated(address indexed updatedBy, address[] accounts, bool[] statuses);

  constructor(address timelockOrOwner) NPM(timelockOrOwner, "Neptune Mutual POT", "POT") {
    whitelist[address(this)] = true;
    whitelist[timelockOrOwner] = true;
  }

  function initialize(IStore store) external onlyOwner {
    require(address(store) != address(0), "Invalid store");
    require(address(s) == address(0), "Already initialized");

    s = store;
    // No need to create an event that is only emitted once
  }

  function _throwIfNotProtocolMember(address account) private view {
    require(address(s) != address(0), "POT not initialized");

    bytes32 key = keccak256(abi.encodePacked(NS_MEMBERS, account));
    bool isMember = s.getBool(key);

    // POTs can only be used within the Neptune Mutual protocol
    require(isMember == true, "Access denied");
  }

  /**
   * @dev Updates whitelisted addresses.
   * Provide a list of accounts and list of statuses to add or remove from the whitelist.
   *
   * @custom:suppress-pausable Risk tolerable
   *
   */
  function updateWhitelist(address[] calldata accounts, bool[] memory statuses) external onlyOwner {
    require(accounts.length > 0, "No account");
    require(accounts.length == statuses.length, "Invalid args");

    for (uint256 i = 0; i < accounts.length; i++) {
      whitelist[accounts[i]] = statuses[i];
    }

    emit WhitelistUpdated(msg.sender, accounts, statuses);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256
  ) internal view override whenNotPaused {
    // Token mints
    if (from == address(0)) {
      // aren't restricted
      return;
    }

    // Someone not whitelisted
    // ............................ can still transfer to a whitelisted address
    if (whitelist[from] == false && whitelist[to] == false) {
      // and to the Neptune Mutual Protocol contracts but nowhere else
      _throwIfNotProtocolMember(to);
    }
  }
}

