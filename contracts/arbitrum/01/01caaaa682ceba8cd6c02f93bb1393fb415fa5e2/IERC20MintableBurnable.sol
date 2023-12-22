//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IERC20MintableBurnable {
    function burn(address from, uint amount) external;
    function mint(address to, uint amount) external;
}
