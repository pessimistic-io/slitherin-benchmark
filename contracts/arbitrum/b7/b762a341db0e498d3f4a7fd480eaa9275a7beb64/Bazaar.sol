//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./ICudlFinance.sol";
import "./IToken.sol";

contract BazaarV1 {
    IToken public milk;
    ICudlFinance public game;
    IToken public token;

    // 1 hibernate / 2 set name / 3 litter /4 milker

    mapping(uint256 => string) public name;
    mapping(uint256 => bool) public isMilker;

    event BazaarItem(uint256 item, uint256 nftId);

    function getPetOwner(uint256 pet) internal view returns (address) {
        address owner;
        (, , , , , , , , owner, , , ) = game.getPetInfo(pet);

        return owner;
    }

    constructor() {
        milk = IToken(0x65A13209467b81dA63866FA0D1D287FB57F611d2);
        game = ICudlFinance(0x048117BBdD9148FBb6a97385533982184dA5067D);
        token = IToken(0x0f4676178b5c53Ae0a655f1B19A96387E4b8B5f2);
    }

    function hibernate(uint256 nftId) public {
        require(getPetOwner(nftId) == msg.sender);
        milk.burnFrom(msg.sender, 100 ether); //TODO amount before deployment
        emit BazaarItem(1, nftId);
        game.addTOD(nftId, 30 days);
    }

    function setName(uint256 nftId, string memory _name) public {
        require(getPetOwner(nftId) == msg.sender);

        milk.burnFrom(msg.sender, 1 ether); //TODO amount before deployment
        name[nftId] = _name;
        emit BazaarItem(2, nftId);
    }

    function litter(uint256 nftId) public {
        require(getPetOwner(nftId) == msg.sender);

        milk.burnFrom(msg.sender, 10 ether); //TODO set amount before deployment

        // add 100 sore
        game.addScore(nftId, 100);
        emit BazaarItem(3, nftId);
    }

    function getMilkerAchievement(uint256 nftId) public {
        require(getPetOwner(nftId) == msg.sender);
        milk.burnFrom(msg.sender, 100 ether); //TODO set amount before deployment
        token.burnFrom(msg.sender, 10 ether); //TODO set amount before deployment
        isMilker[nftId] = true;
        emit BazaarItem(4, nftId);
    }
}

