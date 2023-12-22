// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Types.sol";

interface IConsole {
    function getGame(uint256 _id) external view returns (Types.Game memory);
    function getGameByImpl(address _impl) external view returns (Types.Game memory);
}
