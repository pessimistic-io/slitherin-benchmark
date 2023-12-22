pragma solidity ^0.8.0;

interface IModel {
    function getInterestRate(uint potValue, uint hedgeTV) external view returns (int);
}
