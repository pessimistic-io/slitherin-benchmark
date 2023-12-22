//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC1155Upgradeable} from "./IERC1155Upgradeable.sol";

interface IConsumables is IERC1155Upgradeable {
    function mint(address _to, uint256 _tokenId, uint256 _amount) external;
}

