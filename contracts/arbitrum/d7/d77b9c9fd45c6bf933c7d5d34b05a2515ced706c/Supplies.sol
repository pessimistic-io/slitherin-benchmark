//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Lib } from "./Lib.sol";
import { Ownable } from "./Ownable.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { IBones } from "./IBones.sol";
import {     StringsUpgradeable } from "./StringsUpgradeable.sol";
import { ITreasure } from "./ITreasure.sol";
import {     ERC1155Upgradeable } from "./ERC1155Upgradeable.sol";

import {     LengthsNotEqual,     InvalidTokenId,     NotAuthorized } from "./Error.sol";

contract Supplies is ERC1155Upgradeable, Ownable {
    using StringsUpgradeable for uint256;

    address public laborGround;
    address public treasure;
    address public bones;
    address public magic;

    uint256 public constant MAGIC_PRICE = 10 ether;
    uint256 public constant BONES_PRICE = 1000 ether;
    uint256 public constant TREASURE_MOONROCK_VALUE = 5;

    // uint256 constant SHOVEL = 1;
    // uint256 constant SATCHEL = 2;
    // uint256 constant PICK_AXE = 3;

    string private baseUri;

    enum Curr {
        Magic,
        Bones,
        Treasure
    }

    function initialize(
        address _bones,
        address _magic,
        address _treasure,
        string memory _baseUri
    ) external initializer {
        _initializeOwner(msg.sender);
        bones = _bones;
        magic = _magic;
        treasure = _treasure;
        baseUri = _baseUri;
    }

    function setLaborGroundAddresss(address _laborGround) external onlyOwner {
        laborGround = _laborGround;
    }

    /**
     * this token can no be sold on the secondary market
     * only mint it and used for job
     */

    function mint(
        uint256[] calldata _tokenId,
        uint256[] calldata _amount,
        Curr[] calldata _curr
    ) public {
        uint256 i;
        if (_tokenId.length != _amount.length || _amount.length != _curr.length)
            revert LengthsNotEqual();
        for (; i < _tokenId.length; ++i) {
            if (_tokenId[i] > 3 || _tokenId[i] < 1) revert InvalidTokenId();
            payForToken(_curr[i], _amount[i]);
            _mint(msg.sender, _tokenId[i], _amount[i], "");
        }
    }

    function payForToken(Curr _curr, uint256 _amount) internal {
        if (_curr == Curr.Magic)
            SafeTransferLib.safeTransferFrom(
                magic,
                msg.sender,
                address(this),
                MAGIC_PRICE * _amount
            );
        if (_curr == Curr.Bones)
            IBones(bones).burn(msg.sender, BONES_PRICE * _amount);
        if (_curr == Curr.Treasure)
            ITreasure(treasure).burn(
                msg.sender,
                1,
                TREASURE_MOONROCK_VALUE * _amount
            );
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override {
        if (operator != laborGround) revert NotAuthorized();
        super.setApprovalForAll(operator, approved);
    }

    function burn(address _from, uint256 _id, uint256 _amount) external {
        if (msg.sender != laborGround) revert NotAuthorized();
        _burn(_from, _id, _amount);
    }

    function setBaseUri(string memory _baseUri) external onlyOwner {
        baseUri = _baseUri;
    }

    function name() external pure returns (string memory) {
        return "Supplies";
    }

    function symbol() external pure returns (string memory) {
        return "supplies";
    }

    function withdraw() external onlyOwner {
        SafeTransferLib.safeTransferAll(magic, msg.sender);
    }

    function uri(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return string(abi.encodePacked(baseUri, _tokenId.toString()));
    }
}

