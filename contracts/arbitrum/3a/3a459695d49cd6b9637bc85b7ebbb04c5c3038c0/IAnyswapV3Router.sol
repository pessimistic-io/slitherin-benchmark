pragma solidity ^0.8.0;

interface IAnyswapV3Router {
    function anySwapOutUnderlying(address token, address to, uint amount, uint toChainID) external;
}
