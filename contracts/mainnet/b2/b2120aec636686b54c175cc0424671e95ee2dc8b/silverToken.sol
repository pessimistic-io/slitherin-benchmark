// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./ERC1155Burnable.sol";
import "./Ownable.sol";

/// @custom:security-contact dev@heny.co
contract silverToken is ERC1155, ERC1155Burnable, Ownable {
    constructor() ERC1155("https://www.heny.co") {}

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        onlyOwner
    {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyOwner
    {
        _mintBatch(to, ids, amounts, data);
    }
}

