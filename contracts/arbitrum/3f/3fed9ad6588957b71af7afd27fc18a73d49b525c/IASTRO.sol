// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./IERC20.sol";


interface IASTRO is IERC20 {
    function mintForArbiGobbler(address to, uint256 amount) external;
    function burnForArbiGobbler(address from, uint256 amount) external;
}
