pragma solidity 0.6.6;

interface IWokenCallee {
    function wokenCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

