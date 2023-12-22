// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGamesHub {
    // Events
    event GameContractSet(address _contract, bytes32 _role);
    event GameContractRemoved(address _contract, bytes32 _role);
    event SetAdminWallet(address _adminWallet);
    event ExecutedCall(bytes32 gameName, bytes data, bytes returnData);
    event PlayerRankingChanged(
        address player,
        bytes32 game,
        uint256 volumeIn,
        uint256 volumeOut,
        bool win,
        bool loss
    );
    event NonceIncremented(uint256 nonce);

    // Structs
    struct PlayerRanking {
        bytes32 game;
        uint256 volumeIn;
        uint256 volumeOut;
        uint256 wins;
        uint256 losses;
    }

    // Public Variables
    function games(bytes32) external view returns (address);

    function helpers(bytes32) external view returns (address);

    function adminWallet() external view returns (address);

    function playerRanking(
        address
    ) external view returns (bytes32, uint256, uint256, uint256, uint256);

    function nonce() external view returns (uint256);

    // Constants
    function ADMIN_ROLE() external pure returns (bytes32);

    function DEV_ROLE() external pure returns (bytes32);

    function GAME_CONTRACT() external pure returns (bytes32);

    function NFT_POOL() external pure returns (bytes32);

    function CREDIT_POOL() external pure returns (bytes32);

    // Modifiers
    function setGameContact(
        address _contract,
        bytes32 _name,
        bool _isHelper
    ) external;

    function removeGameContact(
        address _contract,
        bytes32 _name,
        bool _isHelper
    ) external;

    function executeCall(
        bytes32 gameName,
        bytes calldata data,
        bool isHelper,
        bool sendSender
    ) external returns (bytes memory);

    // View Functions
    function getCreditPool() external view returns (address);

    function getNFTPool() external view returns (address);

    function retrieveTimestamp() external view returns (uint256);

    function checkRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    function changePlayerRanking(
        address player,
        bytes32 game,
        uint256 volumeIn,
        uint256 volumeOut,
        bool win,
        bool loss
    ) external;

    function incrementNonce() external;
}

