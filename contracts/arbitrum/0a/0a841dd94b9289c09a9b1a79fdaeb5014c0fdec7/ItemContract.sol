// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

contract ItemContract is OwnableUpgradeable, ERC1155Upgradeable {
    using SafeMathUpgradeable for uint256;

    mapping(address => bool) private adminAccess;
    event SetAdminAccess(address indexed user, bool access);
    string _contractURI;

    function initialize() public initializer {
        __ERC1155_init("");
        __Ownable_init();
    }

    function name() public view virtual returns (string memory) {
        return "Battlefly Items";
    }

    function symbol() public view virtual returns (string memory) {
        return "Battlefly ITEM";
    }

    function contractURI() public view virtual returns (string memory) {
        return _contractURI;
    }

    function mintItems(
        uint256 itemId,
        address receiver,
        uint256 amount,
        bytes memory data
    ) external onlyAdminAccess {
        _mint(receiver, itemId, amount, data);
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }

    function setContractURI(string memory contractURI_) external onlyOwner {
        _contractURI = contractURI_;
    }

    function setURI(string memory uri_) external onlyOwner {
        _setURI(uri_);
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

