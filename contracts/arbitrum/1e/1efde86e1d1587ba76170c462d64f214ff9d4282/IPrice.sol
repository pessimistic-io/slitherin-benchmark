pragma solidity ^0.8.0;

interface IPrice {
    function get() external view returns (uint);
}
