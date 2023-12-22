// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {CreateParams} from "./ERC721Structs.sol";

interface IOmniseaDropsFactory {
    function create(CreateParams calldata params) external;
    function drops(address) external returns (bool);
}

