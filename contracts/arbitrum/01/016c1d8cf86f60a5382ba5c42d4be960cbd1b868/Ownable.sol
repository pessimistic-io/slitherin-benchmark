// SPDX-License-Identifier: UNLICENSED

/**
  /$$$$$$            /$$           /$$      /$$                                        
 /$$__  $$          | $$          | $$$    /$$$                                        
| $$  \ $$ /$$$$$$$ | $$ /$$   /$$| $$$$  /$$$$  /$$$$$$   /$$$$$$  /$$$$$$$   /$$$$$$$
| $$  | $$| $$__  $$| $$| $$  | $$| $$ $$/$$ $$ /$$__  $$ /$$__  $$| $$__  $$ /$$_____/
| $$  | $$| $$  \ $$| $$| $$  | $$| $$  $$$| $$| $$  \ $$| $$  \ $$| $$  \ $$|  $$$$$$ 
| $$  | $$| $$  | $$| $$| $$  | $$| $$\  $ | $$| $$  | $$| $$  | $$| $$  | $$ \____  $$
|  $$$$$$/| $$  | $$| $$|  $$$$$$$| $$ \/  | $$|  $$$$$$/|  $$$$$$/| $$  | $$ /$$$$$$$/
 \______/ |__/  |__/|__/ \____  $$|__/     |__/ \______/  \______/ |__/  |__/|_______/ 
                         /$$  | $$                                                     
                        |  $$$$$$/                                                     
                         \______/                                                      

  https://onlymoons.io/
*/

pragma solidity ^0.8.0;

import { Context } from "./Context.sol";

/**
 * @title Ownable
 * 
 * parent for ownable contracts
 */
abstract contract Ownable is Context {
  constructor(address owner_) {
    _owner_ = owner_;
    emit OwnershipTransferred(address(0), _owner());
  }

  address private _owner_;

  event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

  function _owner() internal view returns (address) {
    return _owner_;
  }

  function owner() external view returns (address) {
    return _owner();
  }

  modifier onlyOwner() {
    require(_owner() == _msgSender(), "Only the owner can execute this function");
    _;
  }

  function _transferOwnership(address newOwner_) virtual internal onlyOwner {
    // keep track of old owner for event
    address oldOwner = _owner();

    // set the new owner
    _owner_ = newOwner_;

    // emit event about ownership change
    emit OwnershipTransferred(oldOwner, _owner());
  }

  function transferOwnership(address newOwner_) external onlyOwner {
    _transferOwnership(newOwner_);
  }
}

