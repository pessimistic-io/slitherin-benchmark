//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface IConsole {
    /*==================== Operational Functions *====================*/

    function addGame(string memory _name, address _impl) external;

    function editGame(uint256 _id, string memory _name, address _impl) external;

    function editGamePauseStatus(bool _value) external;

    function setGasPerRoll(uint256 _gasPerRoll) external;

    /*==================== View Functions *====================*/

    function getId() external view returns (uint256);

    function getGames() external view returns (Types.Game[] memory);

    function getGame(uint256 _id) external view returns (Types.Game memory);

    function getGameWithExtraData(
        uint256 _id,
        address _token
    ) external view returns (Types.GameWithExtraData memory);

    function getImpl(address _impl) external view returns (uint256);

    function getGameByImpl(
        address _impl
    ) external view returns (Types.Game memory);

    function getGasPerRoll() external view returns (uint256);
}

