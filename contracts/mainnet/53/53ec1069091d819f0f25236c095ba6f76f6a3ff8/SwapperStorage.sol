// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import {ISwapper} from "./ISwapper.sol";
import {IMasterOracle} from "./IMasterOracle.sol";

abstract contract SwapperStorage is ISwapper {
    address public nativeToken;

    IMasterOracle public masterOracle;

    mapping(bytes => bytes) public routings;
}

