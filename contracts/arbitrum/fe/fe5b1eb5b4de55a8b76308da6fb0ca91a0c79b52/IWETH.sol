// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.18;

interface IWETH {
    function approve(address spender, uint value) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);

    function deposit() external payable;
    function withdraw(uint amount) external;
}
