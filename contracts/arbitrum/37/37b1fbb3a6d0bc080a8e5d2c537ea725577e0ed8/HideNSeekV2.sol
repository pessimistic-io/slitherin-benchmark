// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IHideNSeekV2.sol";
import "./HideNSeekGameLogicV2.sol";
import "./IBOO.sol";
import "./IPeekABoo.sol";
import "./IStakeManager.sol";
import "./ILevel.sol";

contract HideNSeekV2 is Initializable, IHideNSeekV2, HideNSeekGameLogicV2 {
    function initialize() public initializer {
        __Ownable_init();
        GHOST_COSTS = [20 ether, 30 ether, 40 ether];
        BUSTER_COSTS = [10 ether, 20 ether, 30 ether];
        BUSTER_BONUS = [5 ether, 10 ether];
        ghostReceive = [0 ether, 5 ether, 10 ether];
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
        uint256 activeSessionId;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                peekabooRef.ownerOf(tokenIds[i]) == address(smRef),
                "Not your token."
            );
            smRef.unstakePeekABoo(tokenIds[i]);
            if (peekabooRef.getTokenTraits(tokenIds[i]).isGhost) {
                for (
                    uint256 j = 0;
                    j < TIDtoActiveSessions[tokenIds[i]].length;
                    j++
                ) {
                    activeSessionId = TIDtoActiveSessions[tokenIds[i]][j];
                    removeActiveGhostMap(tokenIds[i], activeSessionId);
                    boo.transfer(
                        TIDtoGMS[tokenIds[i]][activeSessionId].owner,
                        TIDtoGMS[tokenIds[i]][activeSessionId].balance
                    );
                    TIDtoGMS[tokenIds[i]][activeSessionId].balance = 0;
                    TIDtoGMS[tokenIds[i]][activeSessionId].active = false;
                }
            }
        }
    }

    function createGhostMaps(uint256 tId, bytes32[] calldata cmm) external {
        IBOO booRef = boo;
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;

        require(tx.origin == _msgSender(), "No SmartContracts");
        require(
            smRef.isStaked(tId, address(this)),
            "This is not staked in HideNSeek"
        );
        require(peekabooRef.getTokenTraits(tId).isGhost, "Not a ghost");
        require(smRef.ownerOf(tId) == _msgSender(), "This isn't your token");
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
        booRef.transferFrom(msg.sender, address(this), cost * cmm.length);
    }

    function claimGhostMaps(
        uint256 tId,
        uint256[] calldata sId,
        int256[2][] calldata gps,
        uint256[] calldata nonces
    ) external {
        require(sId.length == nonces.length, "Incorrect lengths");
        require(sId.length == gps.length, "Incorrect lengths");
        if (_msgSender() != ACS)
            require(
                sm.isStaked(tId, address(this)) &&
                    sm.ownerOf(tId) == _msgSender(),
                "not staked or not owner"
            );

        for (uint256 i = 0; i < sId.length; i++) {
            claimGhostMap(tId, sId[i], gps[i], nonces[i]);
        }
    }

    function claimBusterSession(uint256 tokenId, uint256 sessionId) external {
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];
        require(gms.busterPlayer == _msgSender(), "must be the buster player");
        require(
            sm.isStaked(tokenId, address(this)),
            "This is not staked in HideNSeek"
        );
        require(
            block.timestamp - 1 days >= gms.playedTime,
            "ghost player has time"
        );

        boo.transfer(gms.busterPlayer, gms.balance);
        emit GameComplete(
            gms.busterPlayer,
            gms.owner,
            tokenId,
            sessionId,
            gms.difficulty,
            gms.balance,
            0
        );
        clearMap(tokenId, sessionId, gms.owner, gms.busterPlayer);
    }

    function generateLockedSession() external {
        require(
            lockedSessions[_msgSender()].lockedBy == address(0x0),
            "Already locked a session"
        );
        uint256 index = pseudoRandom(_msgSender()) % activeSessions.length;
        uint256 count = 0;
        while (activeSessions[index].owner == _msgSender()) {
            require(count < 5, "Preventing infinite loop");
            index =
                (pseudoRandom(_msgSender()) + index) %
                activeSessions.length;
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
        playGame(bi, bp, tokenId, sessionId, BUSTER_COSTS[gms.difficulty]);
        TIDtoGMS[tokenId][sessionId].playedTime = block.timestamp;
        emit PlayedGame(_msgSender(), tokenId, sessionId);
        claimableSessions[gms.owner].push(lockedSessions[_msgSender()]);
        claimableSessions[_msgSender()].push(lockedSessions[_msgSender()]);
        delete lockedSessions[_msgSender()];
    }

    //Admin Access
    function setPeekABoo(address _peekaboo) external onlyOwner {
        peekaboo = IPeekABoo(_peekaboo);
    }

    function setBOO(address _boo) external onlyOwner {
        boo = IBOO(_boo);
    }

    function setStakeManager(address _sm) external onlyOwner {
        sm = IStakeManager(_sm);
    }

    function setLevel(address _level) external onlyOwner {
        level = ILevel(_level);
    }

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

    function setAutoClaimServer(address autoClaimAddress) external onlyOwner {
        ACS = autoClaimAddress;
    }

    function setGhostCost(uint256[3] memory _GHOST_COST) external onlyOwner {
        GHOST_COSTS = _GHOST_COST;
    }

    function setBusterCost(uint256[3] memory _BUSTER_COST) external onlyOwner {
        BUSTER_COSTS = _BUSTER_COST;
    }

    function setBonus(uint256[2] memory _BONUS) external onlyOwner {
        BUSTER_BONUS = _BONUS;
    }

    function numberOfClaimableSessions(address owner)
        external
        view
        returns (uint256)
    {
        return claimableSessions[owner].length;
    }
}

