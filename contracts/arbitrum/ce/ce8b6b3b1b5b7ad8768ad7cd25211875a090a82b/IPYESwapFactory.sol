// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IPYESwapFactory {

    function createPair(
        address tokenA, 
        address tokenB, 
        bool supportsTokenFee, 
        address feeTaker
    ) external returns (
        address pair
    );

    function routerInitialize(address) external;

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint) external view returns (address pair);

    function allPairsLength() external view returns (uint);

    function pairExist(address pair) external view returns (bool);

    function routerAddress() external view returns (address);
    
}

