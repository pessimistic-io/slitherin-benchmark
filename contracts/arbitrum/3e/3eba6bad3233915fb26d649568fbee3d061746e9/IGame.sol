//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IGame {
    // Core funcs
    function editConsole(address _console) external;

    function editVault(address _vault) external;

    function editRNG(address _rng) external;

    function editGameProvider(address _gameProvider) external;

    function pause() external;

    function unpause() external;

    function getId() external view returns (uint256);

    function getConsole() external view returns (address);

    function isPaused() external view returns (bool);

    function getRng() external view returns (address);

    function getVault() external view returns (address);

    function getGameProvider() external view returns (address);

    function getcompletedGames(bytes32 _requestId) external view returns (bool);

    // Game funcs
    function refundGame(bytes32 _requestId) external;

    function play(
        address _token,
        address _frontendReferral,
        uint8 _autoRollAmount,
        uint256 _wager,
        bytes memory _gameData
    ) external payable;
}

