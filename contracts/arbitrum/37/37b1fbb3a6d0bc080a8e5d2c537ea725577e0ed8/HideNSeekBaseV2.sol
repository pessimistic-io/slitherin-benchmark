// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

import "./IHideNSeekV2.sol";
import "./IPeekABoo.sol";
import "./IStakeManager.sol";
import "./IBOO.sol";
import "./ILevel.sol";

contract HideNSeekBaseV2 {
    // reference to the peekaboo smart contract
    IPeekABoo public peekaboo;
    IBOO public boo;
    IStakeManager public sm;
    ILevel public level;
    address ACS;

    mapping(uint256 => mapping(uint256 => IHideNSeekV2.GhostMapSession))
        public TIDtoGMS;
    mapping(uint256 => uint256) public TIDtoNextSessionNumber;
    mapping(uint256 => uint256[]) public TIDtoActiveSessions;
    mapping(address => uint256[2][]) public ownerMatchHistory;
    mapping(address => IHideNSeekV2.Session[]) public claimableSessions;
    mapping(address => IHideNSeekV2.Session) lockedSessions;
    IHideNSeekV2.Session[] activeSessions;

    uint256[3] public GHOST_COSTS;
    uint256[3] public BUSTER_COSTS;
    uint256[2] public BUSTER_BONUS;

    event StakedPeekABoo(address from, uint256 tokenId);
    event UnstakedPeekABoo(address from, uint256 tokenId);
    event ClaimedGhostMap(uint256 tokenId, uint256 sessionId);
    event PlayedGame(address from, uint256 tokenId, uint256 sessionId);
    event GhostMapCreated(
        address indexed ghostPlayer,
        uint256 indexed tokenId,
        uint256 session
    );
    event GameComplete(
        address winner,
        address loser,
        uint256 indexed tokenId,
        uint256 indexed session,
        uint256 difficulty,
        uint256 winnerAmount,
        uint256 loserAmount
    );

    uint256[3] public ghostReceive;
}

