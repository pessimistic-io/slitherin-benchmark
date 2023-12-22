// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ChainUtils.sol";

contract ChainUtils_Mock {

    function getBlockNumbers() external view returns(uint,uint,uint) {
        return (block.chainid, block.number, ChainUtils.getBlockNumber());
    }
}

