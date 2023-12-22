// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

pragma solidity ^0.7.1;

import {DarwinStore} from "./DarwinStore.sol";
import {Proxy, Ownable, Strings, Address, SafeMath, Context} from "./Darwin721.sol";

contract DarwinProxy is  Proxy, DarwinStore{
    constructor(address payable reception) {
      _beneficiary = reception;
    }

    function withdrawalETH() public onlyOwner{
      _beneficiary.transfer(address(this).balance);
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

