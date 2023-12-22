// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

import "./OwnableUpgradeable.sol";
import "./IHideNSeek.sol";
import "./HideNSeekBase.sol";
import "./IPeekABoo.sol";
import "./IBOO.sol";

abstract contract HideNSeekGameLogic is OwnableUpgradeable, HideNSeekBase {
    function playGame(
        uint256[] calldata busterIds,
        int256[2][] calldata busterPos,
        uint256 tokenId,
        uint256 sessionId,
        uint256 cost
    ) internal {
        IPeekABoo peekabooRef = peekaboo;

        boo.transferFrom(_msgSender(), address(this), cost);
        TIDtoGMS[tokenId][sessionId].balance += cost;
        TIDtoGMS[tokenId][sessionId].busterPlayer = _msgSender();
        TIDtoGMS[tokenId][sessionId].numberOfBusters = busterIds.length;
        for (uint256 i = 0; i < busterIds.length; i++) {
            TIDtoGMS[tokenId][sessionId].busterTokenIds[i] = busterIds[i];
            TIDtoGMS[tokenId][sessionId].busterPositions[i] = busterPos[i];
        }
    }

    // Returns true if ghost wins, false if ghost loses
    function verifyGame(
        IHideNSeek.GhostMapSession memory gms,
        uint256 tokenId,
        int256[2] calldata ghostPosition,
        uint256 nonce,
        uint256 sessionId
    ) internal returns (bool) {
        // IPeekABoo peekabooRef = peekaboo;
        IBOO booRef = boo;

        for (uint256 i = 0; i < gms.numberOfBusters; i++) {
            // Ghost reveal logic
            if (
                doesRadiusReveal(
                    gms.busterPositions[i],
                    peekaboo.getTokenTraits(gms.busterTokenIds[i]).revealShape,
                    gms.busterTokenIds[i],
                    ghostPosition
                ) ||
                (
                    gms.busterTokenIds.length == 1
                        ? doesAbilityReveal(
                            gms.busterPositions[i],
                            gms.busterTokenIds[i],
                            ghostPosition
                        )
                        : (
                            gms.busterTokenIds.length == 2
                                ? doesAbilityReveal(
                                    gms.busterPositions[i],
                                    gms.busterTokenIds[i],
                                    ghostPosition,
                                    gms.busterPositions[(i == 0) ? 1 : 0]
                                )
                                : doesAbilityReveal(
                                    gms.busterPositions[i],
                                    gms.busterTokenIds[i],
                                    ghostPosition,
                                    gms.busterPositions[(i == 0) ? 2 : 0],
                                    gms.busterPositions[(i == 1) ? 2 : 1]
                                )
                        )
                )
            ) {
                //Boo Generator Cashing
                // if (peekabooRef.getTokenTraits(gms.busterTokenIds[i]).ability == 6) {
                //     booRef.mint(gms.busterPlayer, 10 ether);
                // }

                return true;
            }
        }
        return false;
    }

    function doesRadiusReveal(
        int256[2] memory busterPosition,
        uint256 revealShape,
        uint256 busterId,
        int256[2] memory ghostPosition
    ) internal view returns (bool) {
        // NormalRevealShape
        if (revealShape == 0) {
            for (int256 i = -1; i <= 1; i++) {
                for (int256 j = -1; j <= 1; j++) {
                    if (
                        (ghostPosition[0] == busterPosition[0] + i &&
                            ghostPosition[1] == busterPosition[1] + j)
                    ) return true;
                }
            }
        }
        // PlusRevealShape
        else if (revealShape == 1) {
            for (int256 i = -2; i <= 2; i++) {
                if (
                    (ghostPosition[0] == busterPosition[0] &&
                        ghostPosition[1] == busterPosition[1] + i) ||
                    (ghostPosition[0] == busterPosition[0] + i &&
                        ghostPosition[1] == busterPosition[1])
                ) return true;
            }
        }
        // XRevealShape
        else if (revealShape == 2) {
            for (int256 i = -2; i <= 2; i++) {
                if (
                    ghostPosition[0] == busterPosition[0] + i &&
                    ghostPosition[1] == busterPosition[1] + i
                ) {
                    return true;
                }
            }
        }

        return false;
    }

    function doesAbilityReveal(
        int256[2] memory busterPosition,
        uint256 busterId,
        int256[2] memory ghostPosition,
        int256[2] memory otherBuster1,
        int256[2] memory otherBuster2
    ) internal view returns (bool) {
        IPeekABoo peekabooRef = peekaboo;
        //LightBuster
        if (peekabooRef.getTokenTraits(busterId).ability == 1) {
            if (ghostPosition[0] == busterPosition[0]) return true;
        }
        //HomeBound
        else if (peekabooRef.getTokenTraits(busterId).ability == 2) {
            if (
                ((busterPosition[0] == otherBuster1[0]) &&
                    (busterPosition[0] == ghostPosition[0])) || // Buster 1 on same row
                ((busterPosition[0] == otherBuster2[0]) &&
                    (busterPosition[0] == ghostPosition[0])) || // Buster 2 on same row
                ((busterPosition[1] == otherBuster1[1]) &&
                    (busterPosition[1] == ghostPosition[1])) || // Buster 1 on same column
                ((busterPosition[1] == otherBuster2[1]) &&
                    (busterPosition[1] == ghostPosition[1]))
            ) // Buster 2 on same column
            {
                return true;
            }
        }
        //GreenGoo
        else if (peekabooRef.getTokenTraits(busterId).ability == 3) {
            if (ghostPosition[1] == busterPosition[1]) {
                return true;
            }
        }
        //StandUnited
        else if (peekabooRef.getTokenTraits(busterId).ability == 4) {
            if (
                isBusterAdjacent(busterPosition, otherBuster1) ||
                isBusterAdjacent(busterPosition, otherBuster2)
            ) {
                for (int256 i = -2; i <= 2; i++) {
                    for (int256 j = -2; i <= 2; i++) {
                        if (
                            (ghostPosition[0] == busterPosition[0] + i &&
                                ghostPosition[1] == busterPosition[1] + j)
                        ) return true;
                    }
                }
            }
        }
        //HolyCross
        else if (peekabooRef.getTokenTraits(busterId).ability == 5) {
            if (
                ghostPosition[0] == busterPosition[0] ||
                ghostPosition[1] == busterPosition[1]
            ) {
                return true;
            }
        }

        return false;
    }

    function doesAbilityReveal(
        int256[2] memory busterPosition,
        uint256 busterId,
        int256[2] memory ghostPosition,
        int256[2] memory otherBuster1
    ) internal view returns (bool) {
        IPeekABoo peekabooRef = peekaboo;
        //LightBuster
        if (peekabooRef.getTokenTraits(busterId).ability == 1) {
            if (ghostPosition[0] == busterPosition[0]) return true;
        }
        //HomeBound
        else if (peekabooRef.getTokenTraits(busterId).ability == 2) {
            if (
                ((busterPosition[0] == otherBuster1[0]) &&
                    (busterPosition[0] == ghostPosition[0])) || // Buster 1 on same row
                ((busterPosition[1] == otherBuster1[1]) &&
                    (busterPosition[1] == ghostPosition[1]))
            ) // Buster 1 on same column
            {
                return true;
            }
        }
        //GreenGoo
        else if (peekabooRef.getTokenTraits(busterId).ability == 3) {
            if (ghostPosition[1] == busterPosition[1]) {
                return true;
            }
        }
        //StandUnited
        else if (peekabooRef.getTokenTraits(busterId).ability == 4) {
            if (isBusterAdjacent(busterPosition, otherBuster1)) {
                for (int256 i = -2; i <= 2; i++) {
                    for (int256 j = -2; i <= 2; i++) {
                        if (
                            (ghostPosition[0] == busterPosition[0] + i &&
                                ghostPosition[1] == busterPosition[1] + j)
                        ) return true;
                    }
                }
            }
        }
        //HolyCross
        else if (peekabooRef.getTokenTraits(busterId).ability == 5) {
            if (
                ghostPosition[0] == busterPosition[0] ||
                ghostPosition[1] == busterPosition[1]
            ) {
                return true;
            }
        }

        return false;
    }

    function doesAbilityReveal(
        int256[2] memory busterPosition,
        uint256 busterId,
        int256[2] memory ghostPosition
    ) internal view returns (bool) {
        IPeekABoo peekabooRef = peekaboo;
        //LightBuster
        if (peekabooRef.getTokenTraits(busterId).ability == 1) {
            if (ghostPosition[0] == busterPosition[0]) return true;
        }
        //GreenGoo
        else if (peekabooRef.getTokenTraits(busterId).ability == 3) {
            if (ghostPosition[1] == busterPosition[1]) {
                return true;
            }
        }
        //HolyCross
        else if (peekabooRef.getTokenTraits(busterId).ability == 5) {
            if (
                ghostPosition[0] == busterPosition[0] ||
                ghostPosition[1] == busterPosition[1]
            ) {
                return true;
            }
        }

        return false;
    }

    function isBusterAdjacent(int256[2] memory pos1, int256[2] memory pos2)
        internal
        pure
        returns (bool)
    {
        int256 difference = pos1[0] + pos1[1] - (pos2[0] + pos2[1]);
        return difference <= 1 && difference >= -1;
    }

    function verifyCommitment(
        uint256 tokenId,
        uint256 sessionId,
        int256[2] calldata ghostPosition,
        uint256 nonce
    ) internal view returns (bool) {
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
            ) == TIDtoGMS[tokenId][sessionId].commitment;
    }

    function hasEnoughBooToFund(
        uint256[] calldata booFundingAmount,
        address sender
    ) internal view returns (bool) {
        uint256 totalBooFundingAmount;
        for (uint256 i = 0; i < booFundingAmount.length; i++) {
            totalBooFundingAmount += booFundingAmount[i];
        }
        return boo.balanceOf(sender) >= totalBooFundingAmount;
    }

    function isNotInBound(uint256 tokenId, int256[2] calldata position)
        internal
        view
        returns (bool)
    {
        IPeekABoo.GhostMap memory ghostMap = peekaboo
            .getGhostMapGridFromTokenId(tokenId);
        if (
            ghostMap.grid[uint256(position[1])][uint256(position[0])] == 1 ||
            position[0] < 0 ||
            position[0] > ghostMap.gridSize - 1 ||
            position[1] < 0 ||
            position[1] > ghostMap.gridSize - 1
        ) {
            return true;
        }
        return false;
    }

    function removeActiveGhostMap(uint256 tokenId, uint256 sessionId) internal {
        for (uint256 i = 0; i < activeSessions.length; i++) {
            if (
                activeSessions[i].tokenId == tokenId &&
                activeSessions[i].sessionId == sessionId
            ) {
                activeSessions[i] = activeSessions[activeSessions.length - 1];
                activeSessions.pop();
                break;
            }
        }
        for (uint256 i = 0; i < TIDtoActiveSessions[tokenId].length; i++) {
            if (TIDtoActiveSessions[tokenId][i] == sessionId) {
                TIDtoActiveSessions[tokenId][i] = TIDtoActiveSessions[tokenId][
                    TIDtoActiveSessions[tokenId].length - 1
                ];
                TIDtoActiveSessions[tokenId].pop();
                return;
            }
        }
    }

    function removeClaimableSession(
        address owner,
        uint256 tokenId,
        uint256 sessionId
    ) internal {
        for (uint256 i = 0; i < claimableSessions[owner].length; i++) {
            if (
                claimableSessions[owner][i].tokenId == tokenId &&
                claimableSessions[owner][i].sessionId == sessionId
            ) {
                claimableSessions[owner][i] = claimableSessions[owner][
                    claimableSessions[owner].length - 1
                ];
                claimableSessions[owner].pop();
                return;
            }
        }
    }
}

