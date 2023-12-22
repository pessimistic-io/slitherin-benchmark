// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC721 } from "./ERC721.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./Math.sol";
import "./SafeMath.sol";



contract Thing is Ownable {

    using SafeMath for uint256;
    using Counters for Counters.Counter;

    address private receiverAddress;
    uint public ccc;
    
    modifier onlyReceiverContract() {
        require(msg.sender == receiverAddress, "Unauthorized access");
        _;
    }


    constructor(address initialOwner) Ownable(initialOwner) {
    // Constructor will be called on contract creation
    // constructor(address initialOwner)  {
        ccc = 9;
    }
    
    function setRecieverContractAddress(address _contractAddress) public onlyOwner() {
        receiverAddress = _contractAddress;
    }



    // TODO this should only be callable by the Shuriken contract
    function doThing(address sender, address recipient, uint256 amount) public onlyReceiverContract() returns (uint256 requestId) {

        ccc++;
    }
    
    function getCCCX() public view returns (uint cccc) {
        return ccc;
    }


}


