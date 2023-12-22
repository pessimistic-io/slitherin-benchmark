// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPepeBet {
    function settleBet(uint256 betID, uint256 closingPrice) external;
}

