// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IPlayerCard} from "./IPlayerCard.sol";

interface IPlayerCardDescriptor {
    function tokenURI(IPlayerCard card, uint256 id) external view returns (string memory);
}

