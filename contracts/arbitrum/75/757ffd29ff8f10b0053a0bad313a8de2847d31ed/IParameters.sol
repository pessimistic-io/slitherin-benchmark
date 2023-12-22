pragma solidity 0.8.17;

interface IParameters {
    function getGrace(address _target) external view returns (uint256);
}

