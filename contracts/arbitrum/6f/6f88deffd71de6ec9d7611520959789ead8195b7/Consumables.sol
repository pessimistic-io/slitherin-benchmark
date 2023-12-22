//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Lib } from "./Lib.sol";
import { Ownable } from "./Ownable.sol";

import { NotAuthorized } from "./Error.sol";
import {     StringsUpgradeable } from "./StringsUpgradeable.sol";
import {     ERC1155Upgradeable } from "./ERC1155Upgradeable.sol";

contract Consumables is ERC1155Upgradeable, Ownable {
    using StringsUpgradeable for uint256;

    // uint256 constant DIRT = 1;
    // uint256 constant HERB = 2;
    // uint256 constant STONES = 3;
    // uint256 constant FERTILE_SOIL = 4;
    // uint256 constant FUNGI = 5;
    // uint256 constant PRECIOUS_MATERIAL = 6;

    string public baseUri;

    mapping(address => bool) public allowedTo;

    function initialize(string memory _baseUri) external initializer {
        _initializeOwner(msg.sender);
        baseUri = _baseUri;
    }

    function setAllowedAddress(address _addr, bool _state) external onlyOwner {
        allowedTo[_addr] = _state;
    }

    function mint(address _to, uint256 _tokenId, uint256 _amount) external {
        if (!allowedTo[msg.sender]) revert NotAuthorized();
        _mint(_to, _tokenId, _amount, "");
    }

    function name() external pure returns (string memory) {
        return "Consumables";
    }

    function symbol() external pure returns (string memory) {
        return "consumables";
    }

    function setBaseUri(string memory _baseUri) external onlyOwner {
        baseUri = _baseUri;
    }

    function uri(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return string(abi.encodePacked(baseUri, _tokenId.toString()));
    }
}

