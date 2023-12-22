// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract IWETH {
    function deposit() external virtual payable;
    function withdraw(uint256 amount) external virtual;
}
