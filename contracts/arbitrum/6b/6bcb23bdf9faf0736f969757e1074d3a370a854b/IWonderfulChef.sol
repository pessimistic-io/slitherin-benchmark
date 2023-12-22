// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import "./IERC20.sol";

interface IWonderfulChef {
    function lpToken(uint256 pid) external view returns (IERC20);

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external;
}
