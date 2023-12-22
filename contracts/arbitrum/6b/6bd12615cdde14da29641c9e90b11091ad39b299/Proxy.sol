// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./IHasUpstream.sol";
import "./FreeMarketBase.sol";

contract Proxy is FreeMarketBase, IHasUpstream {
  constructor(
    address owner,
    address storageAddress,
    address upstream,
    bool userProxy
  ) FreeMarketBase(owner, storageAddress, upstream, userProxy) {}

  function getUpstream() external view virtual returns (address) {
    return upstreamAddress;
  }

  /// @dev this forwards all calls generically to upstream, only the owner can invoke this
  fallback() external payable {
    // enforce owner authz in upstream
    // require(owner == msg.sender);
    _delegate(this.getUpstream());
  }

  /// @dev this allows this contract to receive ETH
  receive() external payable {
    // noop
  }

  /**
   * @dev Delegates execution to an implementation contract.
   * This is a low level function that doesn't return to its internal call site.
   * It will return to the external caller whatever the implementation returns.
   */
  function _delegate(address upstr) internal {
    assembly {
      // Copy msg.data. We take full control of memory in this inline assembly
      // block because it will not return to Solidity code. We overwrite the
      // Solidity scratch pad at memory position 0.
      calldatacopy(0, 0, calldatasize())
      // Call the implementation.
      // out and outsize are 0 because we don't know the size yet.
      let result := delegatecall(gas(), upstr, 0, calldatasize(), 0, 0)
      // Copy the returned data.
      returndatacopy(0, 0, returndatasize())
      switch result
      // delegatecall returns 0 on error.
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
      // let ptr := mload(0x40)
      // calldatacopy(ptr, 0, calldatasize())
      // let result := delegatecall(gas(), implementation, ptr, calldatasize(), 0, 0)
      // let size := returndatasize()
      // returndatacopy(ptr, 0, size)
      // switch result
      // case 0 {
      //   revert(ptr, size)
      // }
      // default {
      //   return(ptr, size)
      // }
    }
  }
}

