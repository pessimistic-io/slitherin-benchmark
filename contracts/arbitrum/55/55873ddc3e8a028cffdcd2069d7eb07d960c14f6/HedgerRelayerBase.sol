// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import {ERC2771Context} from "./ERC2771Context.sol";
import {GelatoRelayContext} from "./GelatoRelayContext.sol";

contract HedgerRelayerBase is ERC2771Context, GelatoRelayContext {
  address internal _owner;
  address internal _trustedForwarder;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  constructor(address trustedForwarder_) ERC2771Context(trustedForwarder_) {
    _transferOwnership(_msgSender());
  }

  /**
   * @dev Throws if called by any account other than the Trusted Forwarder.
   */
  modifier onlyTrustedForwarder() {
    require(isTrustedForwarder(msg.sender), "Only callable by Trusted Forwarder");
    _;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    _checkOwner();
    _;
  }

  /**
   * @dev Returns the address of the current owner.
   */
  function owner() public view virtual returns (address) {
    return _owner;
  }

  /**
   * @dev Returns the address of the trustedForwarder.
   */
  function trustedForwarder() public view virtual returns (address) {
    return _trustedForwarder;
  }

  /**
   * @dev Throws if the sender is not the owner.
   */
  function _checkOwner() internal view virtual {
    require(owner() == _msgSender(), "Ownable: caller is not the owner");
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   * Can only be called by the current owner.
   */
  function transferOwnership(address newOwner) public virtual onlyOwner {
    require(newOwner != address(0), "Ownable: new owner is the zero address");
    _transferOwnership(newOwner);
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   * Internal function without access restriction.
   */
  function _transferOwnership(address newOwner) internal virtual {
    address oldOwner = _owner;
    _owner = newOwner;
    emit OwnershipTransferred(oldOwner, newOwner);
  }
}

