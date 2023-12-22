// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./mock_ERC721A.sol";

contract SoulBoundNFT is ERC721A {
    constructor() ERC721A("SoulBoundNFT", "SBN") {}

    function mint(uint256 quantity) external payable {
        _mint(msg.sender, quantity);
    }

    function _beforeTokenTransfers(address from, address to, uint256 startTokenId, uint256 quantity)
        internal
        virtual
        override(ERC721A)
    {
      require(from == address(0) || to == address(0), "Transfer not allowed");
      super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }
}

