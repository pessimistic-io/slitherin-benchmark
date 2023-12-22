// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface IGameCoordinator {
    function getRewards(address _address) external view returns(uint256);
    function getLevel(address _address) external view returns(uint256);
    function getTotalRolls(address _address) external view returns(uint256);
    function getLastRollTime(address _address) external view returns(uint256);
    function addTotalPlayers(uint256 _amount) external ;
    function addRewards(address _address, uint256 _amount) external;
    function setLevel(address _address, uint256 _level) external;
    function addTotalClaimed(address _address, uint256 _amount) external;
    function addTotalPaid(address _address, uint256 _amount) external;
    function addTotalRolls(address _address) external;
    function setLastRollTime(address _address, uint256 _lastRollTime) external;
    function canPlay(address _player, uint256 _gameId)  external view returns(bool);
    function playerActive(address _player) external view returns(bool);
    function getRentOwed(address _address) external view returns(uint256);
}
