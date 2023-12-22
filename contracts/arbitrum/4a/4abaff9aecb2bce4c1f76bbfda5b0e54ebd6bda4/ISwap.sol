pragma solidity ^0.8.0;

import "./IToken.sol";

interface ISwap {
    function buyHedge(uint amount, address to) external;
    function sellHedge(uint amount, address to) external;
    function buyLeverage(uint amount, address to) external;
    function sellLeverage(uint amount, address to) external;

    function leverageValue(uint amount) external view returns (uint);
    function hedgeValue(uint amount) external view returns (uint, uint);
    function hedgeValueNominal(uint amount) external view returns (uint);

    function updateInterestRate() external;

    function setParameters(address) external;
}

