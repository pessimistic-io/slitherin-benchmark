// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IUNDToken {

    function mint(address _account, uint256 _amount) external;
    function burn(address _account, uint256 _amount) external;
    function balanceOf(address _account) external view returns(uint256);
    function totalSupply() external view returns(uint256);

}
