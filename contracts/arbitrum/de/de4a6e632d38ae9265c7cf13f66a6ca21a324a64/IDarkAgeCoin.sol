// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "./IERC20.sol";

interface IDarkAgeCoin is IERC20 {
    function forge(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function transferAndCall(address _to, uint256 _value, bytes memory _data) external returns (bool);
}

