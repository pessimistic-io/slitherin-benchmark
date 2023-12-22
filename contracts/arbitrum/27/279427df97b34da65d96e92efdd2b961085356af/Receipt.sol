// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./EnumerableSet.sol";

/*
 * vlPNP receipt token
 */
contract RvlPNP is Ownable, ERC20("vlPNP receipt", "rvlPNP") {
  using Address for address;
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private _transferWhitelist; // addresses allowed to send/receive

  constructor() {
    _mint(msg.sender, 1400000000000000000000000);
  }

  /********************************************/
  /****************** EVENTS ******************/
  /********************************************/

  event SetTransferWhitelist(address account, bool add);

  /**************************************************/
  /****************** PUBLIC VIEWS ******************/
  /**************************************************/

  /**
   * @dev returns length of transferWhitelist array
   */
  function transferWhitelistLength() external view returns (uint256) {
    return _transferWhitelist.length();
  }

  /**
   * @dev returns transferWhitelist array item's address for "index"
   */
  function transferWhitelist(uint256 index) external view returns (address) {
    return _transferWhitelist.at(index);
  }

  /**
   * @dev returns if "account" is allowed to send/receive xGRAIL
   */
  function isTransferWhitelisted(address account) external view returns (bool) {
    return _transferWhitelist.contains(account);
  }

  /*******************************************************/
  /****************** OWNABLE FUNCTIONS ******************/
  /*******************************************************/

  /**
   * @dev Adds or removes addresses from the transferWhitelist
   */
  function updateTransferWhitelist(address account, bool add) external onlyOwner {
    require(account != address(this), "updateTransferWhitelist: Cannot remove xGrail from whitelist");

    if(add) _transferWhitelist.add(account);
    else _transferWhitelist.remove(account);

    emit SetTransferWhitelist(account, add);
  }

  /********************************************************/
  /****************** INTERNAL FUNCTIONS ******************/
  /********************************************************/

  /**
   * @dev Hook override to forbid transfers except from whitelisted addresses and minting
   */
  function _beforeTokenTransfer(address from, address to, uint256 /*amount*/) internal view override {
    require(from == address(0) || _transferWhitelist.contains(from) || _transferWhitelist.contains(to), "transfer: not allowed");
  }
}
