pragma solidity =0.5.16;

interface ISpheriumCallee {
    function spheriumCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

