// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IHideNSeek.sol";
import "./HideNSeekGameLogic.sol";
import "./IBOO.sol";
import "./IPeekABoo.sol";
import "./IStakeManager.sol";
import "./ILevel.sol";

contract HideNSeek is Initializable, IHideNSeek, HideNSeekGameLogic {
    function initialize() public initializer {
        __Ownable_init();
        GHOST_COSTS = [20 ether, 30 ether, 40 ether];
        BUSTER_COSTS = [10 ether, 20 ether, 30 ether];
        BUSTER_BONUS = [5 ether, 10 ether];
    }

    function stakePeekABoo(uint256[] calldata tokenIds) external {
        IStakeManager smRef = sm;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            smRef.stakePABOnService(tokenIds[i], address(this), _msgSender());
            emit StakedPeekABoo(_msgSender(), tokenIds[i]);
        }
    }

    function unstakePeekABoo(uint256[] calldata tokenIds) external {
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;
        GhostMapSession memory gms;
        uint256 activeSessionId;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                peekabooRef.ownerOf(tokenIds[i]) == address(smRef),
                "Not your token."
            );
            smRef.unstakePeekABoo(tokenIds[i]);
            emit UnstakedPeekABoo(_msgSender(), tokenIds[i]);
            if (peekabooRef.getTokenTraits(tokenIds[i]).isGhost) {
                for (
                    uint256 j = 0;
                    j < TIDtoActiveSessions[tokenIds[i]].length;
                    j++
                ) {
                    activeSessionId = TIDtoActiveSessions[tokenIds[i]][j];
                    removeActiveGhostMap(tokenIds[i], activeSessionId);
                    gms = TIDtoGMS[tokenIds[i]][activeSessionId];
                    boo.transfer(gms.owner, gms.balance);
                    TIDtoGMS[tokenIds[i]][activeSessionId].balance = 0;
                    TIDtoGMS[tokenIds[i]][activeSessionId].active = false;
                }
            }
        }
    }

    function createGhostMaps(uint256 tokenId, bytes32[] calldata commitments)
        external
        returns (uint256[2] memory sessionsFrom)
    {
        IBOO booRef = boo;
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;

        require(tx.origin == _msgSender(), "No SmartContracts");
        require(
            smRef.isStaked(tokenId, address(this)),
            "This is not staked in HideNSeek"
        );
        require(
            peekabooRef.getTokenTraits(tokenId).isGhost,
            "Not a ghost, can't create GhostMaps"
        );
        require(
            smRef.ownerOf(tokenId) == _msgSender(),
            "This isn't your token"
        );
        require(
            peekabooRef.getGhostMapGridFromTokenId(tokenId).initialized,
            "Ghostmap is not initialized"
        );

        smRef.claimEnergy(tokenId);
        smRef.useEnergy(tokenId, commitments.length);

        uint256 cost = GHOST_COSTS[
            peekabooRef.getGhostMapGridFromTokenId(tokenId).difficulty
        ];
        uint256 total = cost * commitments.length;
        uint256 sessionId;
        sessionsFrom[1] = commitments.length;
        for (uint256 i = 0; i < commitments.length; i++) {
            sessionId = TIDtoNextSessionNumber[tokenId];
            if (i == 0) {
                sessionsFrom[0] = sessionId;
            }
            TIDtoGMS[tokenId][sessionId].active = true;
            TIDtoGMS[tokenId][sessionId].tokenId = tokenId;
            TIDtoGMS[tokenId][sessionId].sessionId = sessionId;
            TIDtoGMS[tokenId][sessionId].difficulty = peekabooRef
                .getGhostMapGridFromTokenId(tokenId)
                .difficulty;
            TIDtoGMS[tokenId][sessionId].cost = cost;
            TIDtoGMS[tokenId][sessionId].balance = cost;
            TIDtoGMS[tokenId][sessionId].commitment = commitments[i];
            TIDtoGMS[tokenId][sessionId].owner = _msgSender();
            TIDtoNextSessionNumber[tokenId] = sessionId + 1;
            TIDtoActiveSessions[tokenId].push(sessionId);
            activeSessions.push(
                Session(tokenId, sessionId, _msgSender(), address(0x0))
            );
            emit GhostMapCreated(msg.sender, tokenId, sessionId);
        }
        booRef.transferFrom(msg.sender, address(this), total);
    }

    function claimGhostMaps(
        uint256 tokenId,
        uint256[] calldata sessionIds,
        int256[2][] calldata ghostPositions,
        uint256[] calldata nonces
    ) external {
        require(
            sessionIds.length == nonces.length,
            "Incorrect lengths for ghostPositions"
        );
        require(
            sessionIds.length == ghostPositions.length,
            "Incorrect lengths for nonces"
        );
        if (_msgSender() != ACS)
            require(
                sm.isStaked(tokenId, address(this)),
                "This is not staked in HideNSeek"
            );

        for (uint256 i = 0; i < sessionIds.length; i++) {
            claimGhostMap(tokenId, sessionIds[i], ghostPositions[i], nonces[i]);
            emit ClaimedGhostMap(tokenId, sessionIds[i]);
        }
    }

    function generateLockedSession() external {
        require(
            lockedSessions[_msgSender()].lockedBy == address(0x0),
            "You already have a locked session"
        );
        uint256 index = pseudoRandom(_msgSender()) % activeSessions.length;
        uint256 count = 0;
        while (activeSessions[index].owner == _msgSender()) {
            require(
                count < 5,
                "Preventing infinite loop, not enough maps you're pseudorandomly being locked into your own maps."
            );
            index =
                (pseudoRandom(_msgSender()) + index) %
                activeSessions.length;
            count++;
        }
        activeSessions[index].lockedBy = _msgSender();
        Session memory session = activeSessions[index];

        lockedSessions[_msgSender()] = session;
        removeActiveGhostMap(session.tokenId, session.sessionId);
    }

    function playGameSession(
        uint256[] calldata busterIds,
        int256[2][] calldata busterPos
    ) external {
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;
        require(
            lockedSessions[_msgSender()].lockedBy != address(0x0),
            "You have not locked in a session yet"
        );
        uint256 tokenId = lockedSessions[_msgSender()].tokenId;
        uint256 sessionId = lockedSessions[_msgSender()].sessionId;
        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];

        for (uint256 i = 0; i < busterIds.length; i++) {
            smRef.claimEnergy(busterIds[i]);
            smRef.useEnergy(busterIds[i], 1);
        }

        require(tx.origin == _msgSender(), "No SmartContracts");
        require(busterIds.length == busterPos.length, "Incorrect lengths");
        require(busterIds.length <= 3, "Can only play with up to 3 busters");
        require(
            peekabooRef.ownerOf(busterIds[0]) == address(smRef),
            "You don't own this buster."
        );
        require(
            !peekabooRef.getTokenTraits(busterIds[0]).isGhost,
            "You can't play with a ghost"
        );
        if (busterIds.length == 2) {
            require(
                peekabooRef.ownerOf(busterIds[1]) == address(smRef),
                "You don't own this buster."
            );
            require(
                !peekabooRef.getTokenTraits(busterIds[1]).isGhost,
                "You can't play with a ghost"
            );
        } else if (busterIds.length == 3) {
            require(
                peekabooRef.ownerOf(busterIds[1]) == address(smRef),
                "You don't own this buster."
            );
            require(
                peekabooRef.ownerOf(busterIds[2]) == address(smRef),
                "You don't own this buster."
            );
            require(
                !peekabooRef.getTokenTraits(busterIds[1]).isGhost,
                "You can't play with a ghost"
            );
            require(
                !peekabooRef.getTokenTraits(busterIds[2]).isGhost,
                "You can't play with a ghost"
            );
        }
        require(gms.owner != _msgSender(), "Cannot Play your own map.");
        require(!isNotInBound(tokenId, busterPos[0]), "buster1 not inbound");
        if (busterIds.length == 2) {
            require(
                !(busterPos[0][0] == busterPos[1][0] &&
                    busterPos[0][1] == busterPos[1][1]),
                "buster1 pos cannot be same as buster2"
            );
            require(
                !isNotInBound(tokenId, busterPos[1]),
                "buster2 not inbound"
            );
        } else if (busterIds.length == 3) {
            require(
                !(busterPos[0][0] == busterPos[1][0] &&
                    busterPos[0][1] == busterPos[1][1]),
                "buster1 pos cannot be same as buster2"
            );
            require(
                !(busterPos[0][0] == busterPos[2][0] &&
                    busterPos[0][1] == busterPos[2][1]),
                "buster1 pos cannot be same as buster3"
            );
            require(
                !(busterPos[1][0] == busterPos[2][0] &&
                    busterPos[1][1] == busterPos[2][1]),
                "buster2 pos cannot be same as buster3"
            );
            require(
                !isNotInBound(tokenId, busterPos[1]),
                "buster2 not inbound"
            );
            require(
                !isNotInBound(tokenId, busterPos[2]),
                "buster3 not inbound"
            );
        }

        playGame(
            busterIds,
            busterPos,
            tokenId,
            sessionId,
            BUSTER_COSTS[gms.difficulty]
        );
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

    // Internal
    function claimGhostMap(
        uint256 tokenId,
        uint256 sessionId,
        int256[2] calldata ghostPosition,
        uint256 nonce
    ) internal {
        IBOO booRef = boo;
        require(
            verifyCommitment(tokenId, sessionId, ghostPosition, nonce),
            "Commitment incorrect, please do not cheat"
        );

        GhostMapSession memory gms = TIDtoGMS[tokenId][sessionId];
        require(gms.active, "Session no longer active");
        uint256 difficulty = gms.difficulty;
        bool notInbound = isNotInBound(tokenId, ghostPosition);

        if (notInbound) {
            booRef.transfer(gms.busterPlayer, gms.balance);
            emit GameComplete(
                gms.busterPlayer,
                gms.owner,
                tokenId,
                sessionId,
                difficulty,
                gms.balance,
                0
            );
        }

        uint256 ghostReceive;
        uint256 busterReceive;
        if (
            !notInbound &&
            verifyGame(gms, tokenId, ghostPosition, nonce, sessionId)
        ) {
            if (gms.numberOfBusters == 1) {
                ghostReceive = 0 * 1 ether;
                busterReceive = gms.balance - ghostReceive;
                booRef.transfer(gms.busterPlayer, busterReceive);
                booRef.mint(gms.busterPlayer, BUSTER_BONUS[1]);
            } else if (gms.numberOfBusters == 2) {
                ghostReceive = 5 * 1 ether;
                busterReceive = gms.balance - ghostReceive;
                booRef.transfer(gms.owner, ghostReceive);
                booRef.transfer(gms.busterPlayer, busterReceive);
                booRef.mint(gms.busterPlayer, BUSTER_BONUS[0]);
            } else {
                ghostReceive = 10 * 1 ether;
                busterReceive = gms.balance - ghostReceive;
                booRef.transfer(gms.owner, ghostReceive);
                booRef.transfer(gms.busterPlayer, busterReceive);
            }
            level.updateExp(tokenId, false, difficulty);
            for (uint256 i = 0; i < gms.numberOfBusters; i++) {
                level.updateExp(gms.busterTokenIds[i], true, difficulty);
            }
            emit GameComplete(
                gms.busterPlayer,
                gms.owner,
                tokenId,
                sessionId,
                difficulty,
                busterReceive,
                ghostReceive
            );
        } else {
            booRef.transfer(gms.owner, gms.balance);
            level.updateExp(tokenId, true, difficulty);
            for (uint256 i = 0; i < gms.numberOfBusters; i++) {
                level.updateExp(gms.busterTokenIds[i], false, difficulty);
            }
            emit GameComplete(
                gms.owner,
                gms.busterPlayer,
                tokenId,
                sessionId,
                difficulty,
                gms.balance,
                0
            );
        }

        TIDtoGMS[tokenId][sessionId].balance = 0;
        TIDtoGMS[tokenId][sessionId].active = false;
        ownerMatchHistory[gms.owner].push([tokenId, sessionId]);
        ownerMatchHistory[gms.busterPlayer].push([tokenId, sessionId]);

        removeClaimableSession(gms.owner, tokenId, sessionId);
        removeClaimableSession(gms.busterPlayer, tokenId, sessionId);
    }

    function pseudoRandom(address sender) internal returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        sender,
                        tx.gasprice,
                        block.timestamp,
                        activeSessions.length,
                        sender
                    )
                )
            );
    }

    function getLockedSession() external returns (Session memory) {
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

    function stillActive(uint256 tokenId, uint256 sessionId)
        external
        view
        returns (bool)
    {
        return TIDtoGMS[tokenId][sessionId].active;
    }

    function matchHistory(address owner)
        external
        view
        returns (GhostMapSession[] memory)
    {
        uint256[2][] memory _matchHistory = ownerMatchHistory[owner];
        GhostMapSession[] memory hideNSeekHistory = new GhostMapSession[](
            _matchHistory.length
        );

        for (uint256 i = 0; i < _matchHistory.length; i++) {
            hideNSeekHistory[i] = TIDtoGMS[_matchHistory[i][0]][
                _matchHistory[i][1]
            ];
        }
        return (hideNSeekHistory);
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

    function createCommitment(
        uint256 tokenId,
        int256[2] calldata ghostPosition,
        uint256 nonce
    ) public pure returns (bytes32) {
        return
            bytes32(
                keccak256(
                    abi.encodePacked(
                        tokenId,
                        ghostPosition[0],
                        ghostPosition[1],
                        nonce
                    )
                )
            );
    }

    function numberOfClaimableSessions(address owner)
        external
        view
        returns (uint256)
    {
        return claimableSessions[owner].length;
    }
}

