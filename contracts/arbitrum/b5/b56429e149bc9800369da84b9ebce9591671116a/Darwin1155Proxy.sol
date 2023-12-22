


// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

pragma experimental ABIEncoderV2;

import {Proxy, ERC1155, Darwin1155Store} from "./Darwin1155.sol";

contract Darwin1155Proxy is  Proxy, Darwin1155Store{
    constructor(string memory uri_) ERC1155(uri_) {
    }
    
    function upgradeTo(address impl) public onlyOwner {
        require(_implementation != impl);
        _implementation = impl;
    }
    
    /**
     * @return The Address of the implementation.
     */
  function implementation() public override virtual view returns (address){
      return _implementation;
  }
    
    
    /**
     * @dev Fallback function.
     * Implemented entirely in `_fallback`.
     */
  fallback () payable external {
    _fallback();
  }

  /**
   * @dev Receive function.
   * Implemented entirely in `_fallback`.
   */
  receive () payable external {
    _fallback();
  }
  
  
}


