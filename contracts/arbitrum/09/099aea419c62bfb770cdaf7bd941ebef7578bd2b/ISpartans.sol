//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import "./IERC721AQueryable.sol";

interface ISpartans is IERC721AQueryable {
    function safeMint(address to, uint256 amount) external;
}

