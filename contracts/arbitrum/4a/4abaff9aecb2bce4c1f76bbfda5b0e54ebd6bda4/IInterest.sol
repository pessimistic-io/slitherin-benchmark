pragma solidity ^0.8.0;

interface IInterest {
    function rate() external view returns (uint);
    function accrewedMul() external view returns (uint);
}

