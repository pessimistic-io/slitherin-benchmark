// SPDX-License-Identifier: None
pragma solidity >=0.5.0;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

interface IAlcorOptionPoolFactory {
    // function getRecipientCallback() external view returns (address);

    function factoryOwner() external view returns (address);

    function parameters() external view returns (address, uint256, uint256, address, address, address, address);
}

