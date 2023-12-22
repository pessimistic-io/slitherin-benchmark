// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./ERC20_IERC20.sol";

interface ILBPair {
    function getTokenX() external view returns (IERC20 tokenX);

    function getTokenY() external view returns (IERC20 tokenY);

    function getBinStep() external view returns (uint16);
}

