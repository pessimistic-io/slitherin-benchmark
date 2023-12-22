pragma solidity ^0.8.4;

interface Idid {
    function isPayFee(address user) external view returns (bool);

    function genId(string memory name) external view returns (bytes32);
    function available(string memory name) external view returns (bool);
    function mint(address to, string memory name) external returns (uint256);
}

