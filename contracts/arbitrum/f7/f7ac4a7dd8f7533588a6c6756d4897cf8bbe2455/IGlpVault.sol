// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IGlpVault {
    function getMinPrice(address) external view returns (uint);
    function PRICE_PRECISION() external view returns (uint);
}
