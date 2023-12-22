pragma solidity >=0.5.0;
// SPDX-License-Identifier: GPL-2.0-or-later
interface IWETH{
    function deposit() external payable;
    function withdraw(uint) external;
}
