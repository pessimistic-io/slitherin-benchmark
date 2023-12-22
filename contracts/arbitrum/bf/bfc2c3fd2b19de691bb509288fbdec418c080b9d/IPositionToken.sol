// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC721Metadata.sol";

interface IPositionToken is IERC721Metadata {
    function burn(uint256 id) external returns (bool);

    function mint(address account, uint256 id) external returns (bool);
}

