pragma solidity ^0.8.0;

interface IHedgeExchanger {

    function hasRole(bytes32 role, address account) external view returns (bool);
}

