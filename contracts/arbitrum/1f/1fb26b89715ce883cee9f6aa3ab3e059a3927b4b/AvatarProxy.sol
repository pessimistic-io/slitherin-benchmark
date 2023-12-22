


// SPDX-License-Identifier: MIT


pragma solidity ^0.7.1;

import {Proxy, ERC721, Ownable, ReentrancyGuarded} from "./Darwin721.sol";


abstract contract AvatarStore is ERC721, ReentrancyGuarded, Ownable{

    constructor(address payable reception, string memory name, string memory symbol) ERC721(name, symbol) {
        _beneficiary = reception;
    }

    address internal _implementation;
    
    //contract trigger
    bool public contractIsOpen = false;

    mapping(address => bool) internal _whiteMap;

    uint256 public MAX_SUPPLY = 5000;

    uint256 internal _whiteMintCount;

    uint256 internal _mintStartTime;

    address  payable internal _beneficiary;
}

contract AvatarProxy is  Proxy, AvatarStore{
    constructor(address payable reception, string memory name, string memory symbol) AvatarStore(reception, name, symbol) {
        
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


