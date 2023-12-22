// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGovNFT {
    function distribute(address _tigAsset, uint _amount) external;
}
