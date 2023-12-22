// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

interface IHideNSeek {
    struct GhostMapSession {
        bool active;
        uint256 tokenId;
        uint256 sessionId;
        uint256 difficulty;
        uint256 cost;
        uint256 balance;
        bytes32 commitment;
        address owner;
        address busterPlayer;
        uint256 numberOfBusters;
        uint256[3] busterTokenIds;
        int256[2][3] busterPositions;
    }

    struct Session {
        uint256 tokenId;
        uint256 sessionId;
        address owner;
        address lockedBy;
    }

    function stakePeekABoo(uint256[] calldata tokenIds) external;

    function unstakePeekABoo(uint256[] calldata tokenIds) external;

    function claimGhostMaps(
        uint256 tokenId,
        uint256[] calldata sessionIds,
        int256[2][] calldata ghostPositions,
        uint256[] calldata nonces
    ) external;

    function playGameSession(
        uint256[] calldata busterIds,
        int256[2][] calldata busterPos
    ) external;

    function getGhostMapSessionStats(uint256 tokenId, uint256 sessionId)
        external
        view
        returns (GhostMapSession memory);

    function getLockedSession() external returns (Session memory);

    function getTokenIdActiveSessions(uint256 tokenId)
        external
        view
        returns (uint256[] memory);

    function stillActive(uint256 tokenId, uint256 sessionId)
        external
        view
        returns (bool);

    function matchHistory(address owner)
        external
        view
        returns (GhostMapSession[] memory);

    function numberOfClaimableSessions(address owner)
        external
        view
        returns (uint256);
}

