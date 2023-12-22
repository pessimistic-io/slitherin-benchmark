// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

interface IWarehouse {
    function add(address, uint256, address) external;
    function recover(address, uint256) external;
}
