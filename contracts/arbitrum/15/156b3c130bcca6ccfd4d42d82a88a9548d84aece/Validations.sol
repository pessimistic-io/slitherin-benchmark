//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./PositionNFT.sol";
import "./DataTypes.sol";

function validateCreatePositionPermissions(PositionNFT positionNFT, address onBehalfOf) view {
    if (!positionNFT.isApprovedForAll(onBehalfOf, msg.sender)) revert Unauthorised(msg.sender);
}

function validateModifyPositionPermissions(PositionNFT positionNFT, PositionId positionId)
    view
    returns (address positionOwner)
{
    positionOwner = positionNFT.positionOwner(positionId);
    if (positionOwner != msg.sender && !positionNFT.isApprovedForAll(positionOwner, msg.sender)) {
        revert Unauthorised(msg.sender);
    }
}

