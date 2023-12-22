// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./OmniseaONFT721Psi.sol";
import "./IOmniseaDropsRepository.sol";
import { CreateParams } from "./ERC721Structs.sol";

contract OmniseaDropsRepository is IOmniseaDropsRepository {
    address public dropsFactory;
    address public dropsManager;
    address public owner;
    mapping(address => address[]) public userCollections;
    mapping(address => bool) public collections;

    constructor () {
        owner = msg.sender;
    }

    function create(
        CreateParams calldata _params,
        address _creator
    ) external override {
        require(msg.sender == dropsFactory);

        OmniseaONFT721Psi collection = new OmniseaONFT721Psi(_params, _creator, dropsManager);
        userCollections[_creator].push(address(collection));
        collections[address(collection)] = true;
    }

    function getAllByUser(address user) external view returns (address[] memory) {
        return userCollections[user];
    }

    function setFactory(address factory) external {
        require(msg.sender == owner);
        dropsFactory = factory;
    }

    function setManager(address factory) external {
        require(msg.sender == owner);
        dropsManager = factory;
    }
}

