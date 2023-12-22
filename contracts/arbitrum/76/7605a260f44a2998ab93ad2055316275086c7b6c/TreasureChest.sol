// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC1155SupplyUpgradeable} from "./ERC1155SupplyUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {EnumerableSetUpgradeable} from "./EnumerableSetUpgradeable.sol";

import {ITreasureChest} from "./ITreasureChest.sol";

contract TreasureChest is OwnableUpgradeable, ERC1155SupplyUpgradeable, ITreasureChest {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    string public name;
    string public symbol;
    string public contractURI;

    EnumerableSetUpgradeable.AddressSet private _auth;

    function __TreasureChest_init(
        string memory name_,
        string memory symbol_,
        string memory uri_
    ) external initializer {
        __Ownable_init_unchained();
        __ERC1155_init(uri_);

        name = name_;
        symbol = symbol_;
        _auth.add(msg.sender);
    }

    function mint(address recipient) external {
        require(_auth.contains(msg.sender), "unauthorized");
        _mint(recipient, 1, 1, "");
    }

    function setAuth(address authAddr, bool added) external onlyOwner {
        added ? _auth.add(authAddr) : _auth.remove(authAddr);
    }

    function setUri(string memory newUri) external onlyOwner {
        _setURI(newUri);
    }

    function setContractURI(string memory newContractURI) external onlyOwner {
        contractURI = newContractURI;
    }

    function allAuth() external view returns (address[] memory){
        return _auth.values();
    }

    function uri(uint id) public view override returns (string memory) {
        require(id == 1, "invalid id");
        return super.uri(1);
    }

    function totalSupply() external view returns (uint){
        return totalSupply(1);
    }

    uint[45] private __gap;
}

