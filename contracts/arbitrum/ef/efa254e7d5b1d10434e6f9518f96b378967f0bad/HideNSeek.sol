// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IHideNSeekV2.sol";
import "./HideNSeekGameLogicV3.sol";
import "./IBOO.sol";
import "./IPeekABoo.sol";
import "./IStakeManager.sol";
import "./ILevel.sol";

contract HideNSeek is Initializable, IHideNSeekV2, HideNSeekGameLogicV3 {
    function initialize() public initializer {
        __Ownable_init();
        GHOST_COSTS = [20 ether, 30 ether, 40 ether];
        BUSTER_COSTS = [10 ether, 20 ether, 30 ether];
        BUSTER_BONUS = [5 ether, 10 ether];
        ghostReceive = [0 ether, 5 ether, 10 ether];
    }

    modifier onlyStakedOwner(uint256 tId) {
        require(
            sm.isStaked(tId, address(this)) && sm.ownerOf(tId) == _msgSender(),
            "not staked or not owner"
        );
        _;
    }

    function stakePeekABoo(uint256[] calldata tokenIds) external {
        IStakeManager smRef = sm;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            smRef.stakePABOnService(tokenIds[i], address(this), _msgSender());
        }
    }

    function unstakePeekABoo(uint256[] calldata tokenIds) external {
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;
        uint256 asId = 0;
        uint256 len = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                smRef.ownerOf(tokenIds[i]) == _msgSender(),
                "Not your token."
            );
            smRef.unstakePeekABoo(tokenIds[i]);
            if (peekabooRef.getTokenTraits(tokenIds[i]).isGhost) {
                len = TIDtoActiveSessions[tokenIds[i]].length;
                for (uint256 j = 0; j < len; j++) {
                    asId = TIDtoActiveSessions[tokenIds[i]][0];
                    removeActiveGhostMap(tokenIds[i], asId);
                    boo.transfer(
                        TIDtoGMS[tokenIds[i]][asId].owner,
                        TIDtoGMS[tokenIds[i]][asId].balance
                    );
                    TIDtoGMS[tokenIds[i]][asId].balance = 0;
                    TIDtoGMS[tokenIds[i]][asId].active = false;
                }
            }
        }
    }

    function createGhostMaps(uint256 tId, bytes32[] calldata cmm)
        external
        onlyStakedOwner(tId)
    {
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;

        require(peekabooRef.getTokenTraits(tId).isGhost, "Not a ghost");
        require(
            peekabooRef.getGhostMapGridFromTokenId(tId).initialized,
            "Ghostmap is not initialized"
        );

        smRef.claimEnergy(tId);
        smRef.useEnergy(tId, cmm.length);

        uint256 difficulty = peekabooRef
            .getGhostMapGridFromTokenId(tId)
            .difficulty;
        uint256 cost = GHOST_COSTS[difficulty];
        uint256 sId;
        for (uint256 i = 0; i < cmm.length; i++) {
            sId = TIDtoNextSessionNumber[tId];
            TIDtoGMS[tId][sId].active = true;
            TIDtoGMS[tId][sId].tokenId = tId;
            TIDtoGMS[tId][sId].sessionId = sId;
            TIDtoGMS[tId][sId].difficulty = difficulty;
            TIDtoGMS[tId][sId].cost = cost;
            TIDtoGMS[tId][sId].balance = cost;
            TIDtoGMS[tId][sId].commitment = cmm[i];
            TIDtoGMS[tId][sId].owner = _msgSender();
            TIDtoNextSessionNumber[tId] = sId + 1;
            TIDtoActiveSessions[tId].push(sId);
            activeSessions.push(Session(tId, sId, _msgSender(), address(0x0)));
            emit GhostMapCreated(msg.sender, tId, sId);
        }
        boo.transferFrom(msg.sender, address(this), cost * cmm.length);
    }

    function claimGhostMaps(
        uint256 tId,
        uint256[] calldata sId,
        int256[2][] calldata gps,
        uint256[] calldata nonces
    ) external onlyStakedOwner(tId) {
        require(
            sId.length == nonces.length && sId.length == gps.length,
            "Incorrect lengths"
        );
        if (_msgSender() != ACS)
            for (uint256 i = 0; i < sId.length; i++) {
                claimGhostMap(tId, sId[i], gps[i], nonces[i]);
            }
    }

    function rescueSession(uint256 tokenId, uint256 sessionId)
        external
        onlyOwner
    {
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];

        boo.transfer(gms.owner, gms.cost);
        boo.transfer(gms.busterPlayer, gms.balance - gms.cost);
        clearMap(tokenId, sessionId, gms.owner, gms.busterPlayer);
    }

    function claimBusterSession(uint256 tokenId, uint256 sessionId) external {
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];
        require(gms.active, "Session no longer active");
        require(gms.busterPlayer == _msgSender(), "must be the buster player");
        require(
            block.timestamp - 1 days >= gms.playedTime,
            "ghost player has time"
        );

        updateExp(gms, false, true);
        boo.transfer(gms.busterPlayer, gms.balance);
        clearMap(tokenId, sessionId, gms.owner, gms.busterPlayer);
    }

    function generateLockedSession() external {
        require(
            lockedSessions[_msgSender()].lockedBy == address(0x0),
            "Already locked a session"
        );
        uint256 index = pseudoRandom(_msgSender()) % activeSessions.length;
        uint256 count = 0;
        uint256 tokenId = activeSessions[index].tokenId;
        uint256 sessionId = activeSessions[index].sessionId;
        while (activeSessions[index].owner == _msgSender() || TIDtoGMS[tokenId][sessionId].active == false) {
            require(count < 5, "Preventing infinite loop");
            index =
                (pseudoRandom(_msgSender()) + index) %
                activeSessions.length;
            tokenId = activeSessions[index].tokenId;
            sessionId = activeSessions[index].sessionId;
            count++;
        }
        activeSessions[index].lockedBy = _msgSender();
        Session memory session = activeSessions[index];
        GhostMapSession memory gms = TIDtoGMS[session.tokenId][
            session.sessionId
        ];

        boo.transferFrom(
            _msgSender(),
            address(this),
            BUSTER_COSTS[gms.difficulty]
        );
        TIDtoGMS[session.tokenId][session.sessionId].balance += BUSTER_COSTS[
            gms.difficulty
        ];
        lockedSessions[_msgSender()] = session;
        TIDtoGMS[session.tokenId][session.sessionId].lockedTime = block
            .timestamp;
        removeActiveGhostMap(session.tokenId, session.sessionId);
    }

    function playGameSession(uint256[] calldata bi, int256[2][] calldata bp)
        external
    {
        IStakeManager smRef = sm;
        require(
            lockedSessions[_msgSender()].lockedBy != address(0x0),
            "You have not locked in a session yet"
        );
        uint256 tokenId = lockedSessions[_msgSender()].tokenId;
        uint256 sessionId = lockedSessions[_msgSender()].sessionId;
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];

        for (uint256 i = 0; i < bi.length; i++) {
            smRef.claimEnergy(bi[i]);
            smRef.useEnergy(bi[i], 1);
        }

        playRequirements(bi, bp, tokenId);
        playGame(bi, bp, tokenId, sessionId);
        TIDtoGMS[tokenId][sessionId].playedTime = block.timestamp;
        emit PlayedGame(_msgSender(), tokenId, sessionId);
        claimableSessions[gms.owner].push(lockedSessions[_msgSender()]);
        claimableSessions[_msgSender()].push(lockedSessions[_msgSender()]);
        delete lockedSessions[_msgSender()];
    }

    //Admin Access
    function getLockedSession() external view returns (Session memory) {
        return lockedSessions[_msgSender()];
    }

    // Public READ Game Method
    function getGhostMapSessionStats(uint256 tokenId, uint256 sessionId)
        external
        view
        returns (GhostMapSession memory)
    {
        return TIDtoGMS[tokenId][sessionId];
    }

    function getTokenIdActiveSessions(uint256 tokenId)
        external
        view
        returns (uint256[] memory)
    {
        return TIDtoActiveSessions[tokenId];
    }

    function matchHistory(address owner)
        external
        view
        returns (GhostMapSession[] memory)
    {
        uint256[2][] memory mh = ownerMatchHistory[owner];
        GhostMapSession[] memory hnsHistory = new GhostMapSession[](mh.length);

        for (uint256 i = 0; i < mh.length; i++) {
            hnsHistory[i] = TIDtoGMS[mh[i][0]][mh[i][1]];
        }
        return hnsHistory;
    }

    function numberOfClaimableSessions(address owner)
        external
        view
        returns (uint256)
    {
        return claimableSessions[owner].length;
    }
}

