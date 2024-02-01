// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC721A.sol";

interface INftCollection is IERC721A {
    function maxSupply() external view returns (uint256);

    function mint(address to, uint256 quantity) external;
}

