// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./IERC20.sol";

interface IStrategy {
    function vault() external view returns (address);
    function want() external view returns (IERC20);
    function beforeDeposit() external;
    function deposit() external;
    function withdraw(uint256) external;
    function balanceOf() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function harvest() external;
    function panic() external;
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
    function unirouter() external view returns (address);

    function pool() external view returns (address);
    function poolSize() external view returns (uint256);
    function preferredUnderlyingToken() external returns (string memory);
    function underlyingTokenAddress(string memory _token) external returns (address);
    function underlyingTokenIndex(string memory _token) external returns (uint256);
}

