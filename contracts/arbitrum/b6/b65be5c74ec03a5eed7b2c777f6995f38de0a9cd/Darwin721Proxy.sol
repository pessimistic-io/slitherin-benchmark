


// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

pragma experimental ABIEncoderV2;
import {Proxy, Darwin721} from "./Darwin721.sol";

contract Darwin721Proxy is  Proxy, Darwin721{
    constructor(string memory name, string memory symbol) Darwin721(name, symbol) {
        
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
  


