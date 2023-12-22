// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Types.sol";

interface IHouse {
    function openWager(address _account, uint256 _game, uint256 _rolls, uint256 _bet, uint256[50] calldata _data, uint256 _betSize, uint256 _maxPayout) external returns (uint256, uint256);
    function closeWager(uint256 betId, address _account, uint256 _gameId, uint256 _payout) external returns (bool);
    function getBet(uint256 _id) external view returns (Types.Bet memory);
}

