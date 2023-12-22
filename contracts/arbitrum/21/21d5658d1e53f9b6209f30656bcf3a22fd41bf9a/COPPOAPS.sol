// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1155Upgradeable, ContextUpgradeable} from "./ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "./ERC2771ContextUpgradeable.sol";
import {Strings} from "./Strings.sol";

error OutsideSaleWindow();
error AlreadyClaimed();

contract CommunitiesOfPracticePOAPs is UUPSUpgradeable, OwnableUpgradeable, ERC1155Upgradeable, ERC2771ContextUpgradeable {
    struct ClaimWindow {
        uint128 startTime;
        uint128 endTime;
    }

    mapping(uint256 => ClaimWindow) public claimWindows;
    mapping(address => bool) public claimed;

    function __CommunitiesOfPracticePOAPs_init(address initialOwner, string calldata uri_) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(initialOwner);
        __ERC1155_init(uri_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    constructor (address trustedForwarder_) ERC2771ContextUpgradeable(trustedForwarder_) {
        _disableInitializers();
    }

    function claim (uint256 tokenId) external {
        ClaimWindow memory claimWindow = claimWindows[tokenId];
        if (block.timestamp < claimWindow.startTime || block.timestamp > claimWindow.endTime) revert OutsideSaleWindow();
        address claimer = _msgSender();
        if (claimed[claimer]) revert AlreadyClaimed();
        claimed[claimer] = true;

        _mint(claimer, tokenId, 1, "");
    }

    function setClaimWindow(uint256 tokenId, uint128 startTime, uint128 endTime) external onlyOwner {
        claimWindows[tokenId] = ClaimWindow(startTime, endTime);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory _uri = super.uri(tokenId);
        return string(abi.encodePacked(_uri, Strings.toString(tokenId), ".json"));
    }

    function setURI (string memory newURI) external onlyOwner {
        _setURI(newURI);
    } 

    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return super._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return super._msgData();
    }

    
}

