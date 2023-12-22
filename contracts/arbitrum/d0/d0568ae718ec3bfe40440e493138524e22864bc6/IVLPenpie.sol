// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "./ERC20.sol";
import "./ILocker.sol";

interface IVLPenpie is ILocker {
    
    function penpie() external view returns(IERC20);
}
