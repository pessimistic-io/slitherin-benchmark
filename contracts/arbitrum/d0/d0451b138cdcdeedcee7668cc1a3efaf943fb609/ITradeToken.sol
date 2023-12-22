// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface ITradeToken {
    function mint(address _account, uint256 _amount) external;
    function burn(address _account, uint256 _amount) external;
}

