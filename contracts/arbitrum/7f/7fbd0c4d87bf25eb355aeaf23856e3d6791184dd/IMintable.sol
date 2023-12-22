// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IMintable {
    function mint(address recipient, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

