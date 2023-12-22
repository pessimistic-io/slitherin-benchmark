// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

pragma solidity ^0.7.1;

import {DarwinSBT,Proxy, ERC721, ReentrancyGuarded, Ownable, Strings, Address, SafeMath, Context} from "./Darwin721.sol";
import {IERC20} from "./IERC20.sol";

/*
    The contract is about terra-darwin
    The feature include:
    1,Mutiple character
    2,claim-Armory
    3,claim-1155 Resource 
    4,Mint-land
    5,Stack-Armory
    6,Stack-1155
*/
abstract contract  DarwinStore is ReentrancyGuarded, Ownable{
    /* An ECDSA signature. */ 
    struct Sig {
        /* v parameter */
        uint8 v;
        /* r parameter */
        bytes32 r;
        /* s parameter */
        bytes32 s;
    }

    /* An order on the exchange. */
    struct Order {
        uint256 orderId;

        uint256 tokenId;

        uint256 tokenTag;

        uint[]  consumeId;

        uint[]  consumeAmount;        
    }


    address internal _implementation;
     
    //contract trigger
    bool public contractIsOpen = false;

    address internal _armoryNFT;

    address internal _characterNFT;

    address internal _NFT1155;

    mapping(uint256 => bool) internal _orderIdMap;

    mapping(uint256 => address) internal _stackArmoryMap;

    mapping(uint256 => mapping(address => uint256)) internal _stack1155Map;

    address  payable internal _beneficiary;

    mapping(uint256 => uint256) internal _pfpCharacterMap;

    /*
    * Pause sale if active, make active if paused
    */
    function flipContractState() public onlyOwner {
        contractIsOpen = !contractIsOpen;
    }


    function armoryNFT() public view returns (address){
        return _armoryNFT;
    }

    function characterNFT() public view returns (address){
        return _characterNFT;
    }

    function nft1155() public view returns (address){
        return _NFT1155;
    }

    function setArmoryNFT(address addr) public virtual onlyOwner {
        _armoryNFT = addr;
    }

    function setNFT1155(address addr) public virtual onlyOwner {
        _NFT1155 = addr;
    }

    function setCharacterNFT(address addr) public virtual onlyOwner {
        _characterNFT = addr;
    }
}


