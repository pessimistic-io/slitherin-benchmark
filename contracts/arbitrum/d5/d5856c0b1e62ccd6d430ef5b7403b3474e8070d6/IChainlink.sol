pragma solidity ^0.8.6;

interface IChainlink {
    function latestAnswer() external view returns(uint256);
}
