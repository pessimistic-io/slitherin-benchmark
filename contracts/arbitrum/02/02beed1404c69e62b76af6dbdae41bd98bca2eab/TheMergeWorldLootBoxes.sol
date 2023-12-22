// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC1155Supply.sol";

contract TheMergeWorldLootBoxes is ERC1155Supply, Ownable {

    string public name = "The Merge World Lootboxes";
    string public symbol = "TMWL";

    constructor() ERC1155("https://storage.googleapis.com/posersnft/lootboxes-meta/{id}") {
    }

    function setURI(string memory uri) external onlyOwner {
        _setURI(uri);
    }

    function airdrop(uint tokenId, address[] calldata accounts, uint[] calldata amounts) external onlyOwner {
        require(accounts.length == amounts.length, "accounts.length == amounts.length");
        for (uint i = 0; i < accounts.length; i++) {
            _mint(accounts[i], tokenId, amounts[i], "");
        }
    }

    function burn(uint tokenId, uint amount) external {
        require(amount > 0, "amount param has to be positive");
        _burn(msg.sender, tokenId, amount);
    }

    function totalSupply() external view returns(uint) {
        uint res = 0;
        for (uint i = 0; i < 300; i++) {
            res += totalSupply(i);
        }
        return res;
    }
}
