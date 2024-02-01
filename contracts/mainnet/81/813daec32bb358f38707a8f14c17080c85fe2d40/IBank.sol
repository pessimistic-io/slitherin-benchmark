// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";
import {TokenType} from "./TokenEnums.sol";
import {NFT} from "./BaseStructs.sol";

interface IBank is IERC165 {
    function bindMarket(address market_) external;
}

