


// SPDX-License-Identifier: MIT


pragma solidity ^0.7.1;

import {Proxy, ERC721, Ownable, ReentrancyGuarded} from "./Darwin721.sol";
import {AvatarStore} from "./AvatarProxy.sol";

contract Avatar is  AvatarStore{
    constructor(address payable reception, string memory name, string memory symbol) AvatarStore(reception, name, symbol) {
        
    }
    
    function version() public pure returns (uint){
        return 1;
    }

    function canMint(address addr) public view returns (bool){
         uint8 chapeN = chapeIndex();

        if(chapeN == 0){
            return false;
        }

        if(balanceOf(addr) >= 10){
            return false;
        }
        
        if(chapeN == 1){
            if(isWhiteAddr(addr) && whiteMintCount() < whiteMintMax()){
                return true;
            }else{
                return false;
            }
        }
        if(totalSupply() >= MAX_SUPPLY){
            return false;
        }
        return true;
    }


    function isWhiteAddr(address addr) public view returns (bool){
        return _whiteMap[addr];
    }

    function whiteMintMax() public pure returns (uint32) {
        return 1000;
    }

    function whiteMintCount() public view returns (uint256){
        return _whiteMintCount;
    }

    function whiteMinTime() public view returns (uint256){
        return _mintStartTime + 86400;
    }

    function chapeIndex() public view returns(uint8){
        if(_mintStartTime == 0){
            return 0;
        }
        if(block.timestamp < _mintStartTime){
            return 0;
        }
        if(block.timestamp <= whiteMinTime()){
            return 1;
        }
        return 2;
    }


    function avatarPrice(address addr) public view returns (uint256){
        //Whitelist Mint   0.02eth
        //Community Mint    0.025eth
        //uint256 price = 25000000000000000;
        //uint256 whitePrice = 20000000000000000;

        //--test price = 0.00025
        //--test whiteprice = 0.0002
        uint256 price = 250000000000000;
        uint256 whitePrice = 200000000000000;
        //1K white name max
        if(!isWhiteAddr(addr) || chapeIndex() != 1 || whiteMintCount() >= whiteMintMax()){
            return price;
        }
        
        return whitePrice;
        
    }


    function mint() public payable reentrancyGuard{
        require(contractIsOpen, "Contract must active");
        
        require(totalSupply() < MAX_SUPPLY, "Mint finished");

        uint8 chapeN = chapeIndex();

        require(chapeN > 0, "Mint not start");

        require(canMint(msg.sender), "You can't mint");

        require(avatarPrice(msg.sender) == msg.value, "Price unmatch");
        
        uint256 tokenId = totalSupply() + 1;

        _safeMint(msg.sender, tokenId);

        if(isWhiteAddr(msg.sender)){
            _whiteMintCount ++;
        }
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _setBaseURI(baseURI);
    }

    function reserveMint(uint count) public onlyOwner reentrancyGuard{
        require(contractIsOpen, "Contract must active");

        for(uint i=0; i<count; ++i){
            uint256 tokenId = totalSupply() + 1;
            _safeMint(msg.sender, tokenId);
        }
    }
}




