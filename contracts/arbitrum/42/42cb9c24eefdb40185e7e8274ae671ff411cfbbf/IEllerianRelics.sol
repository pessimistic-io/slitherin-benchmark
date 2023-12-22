pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

// Interface for Ellerian Relics.
contract IEllerianRelics {
    function mint(address to, uint256 id, uint256 amount) external { }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) external {}

    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) external {}

    function externalMint(address to, uint256 id, uint256 amount) external {}
}
