// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IUniswapPair {
    /// @return Returns the address of the Uniswap V3 factory
    function factory() external view returns (address);
}

