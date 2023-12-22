// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;


interface ILpDepositor {
    function transferDeposit(address _token, address _from, address _to, uint256 _amount) external returns (bool);
    function userBalances(address _user, address _token) external view returns (uint256);
    function totalBalances(address _token) external view returns (uint256);
}
