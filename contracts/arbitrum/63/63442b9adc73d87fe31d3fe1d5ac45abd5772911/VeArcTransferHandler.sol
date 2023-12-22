// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IArc} from "./IArc.sol";
import {IHandler} from "./IHandler.sol";
import {IMintBurn} from "./IMintBurn.sol";
import {IVotingEscrow} from "./IVotingEscrow.sol";

/**
 * Dex Weekly Update Handler
 */
contract VeArcTransferHandler is ArcBaseWithRainbowRoad, IHandler
{
    uint internal constant WEEK = 1 weeks;
    uint internal constant MAXTIME = 4 * 365 * 86400;
    IVotingEscrow public veArc;
    
    event VeArcMinted(address indexed account, uint fromTokenId, uint toTokenId, uint amount, uint fromLockEnd, uint toLockEnd);
    event VeArcReceived(address indexed operator, address indexed from, uint tokenId, bytes data);
    
    constructor(address _rainbowRoad, address _veArc) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        require(_veArc != address(0), 'veArc cannot be zero address');
        veArc = IVotingEscrow(_veArc);
    }
    
    function setVeArc(address _veArc) external onlyOwner
    {
        require(_veArc != address(0), 'veArc cannot be zero address');
        veArc = IVotingEscrow(_veArc);
    }
    
    function encodePayload(uint tokenId) view external returns (bytes memory payload)
    {
        uint lockedAmount = veArc.locked__amount(tokenId);
        uint lockedEnd = veArc.locked__end(tokenId);
        uint blockTimestamp = block.timestamp;
        
        uint lockDuration = lockedEnd - blockTimestamp;
        require(lockDuration > 0, 'veArc cannot be expired');
        
        uint unlockTime = (blockTimestamp + lockDuration) / WEEK * WEEK; // Locktime is rounded down to weeks
        require(unlockTime > blockTimestamp, 'Lock cannot expire soon');
        require(unlockTime <= blockTimestamp + MAXTIME, 'Cannot be locked for more than 4 years');
        
        return abi.encode(tokenId, lockedAmount, lockedEnd);
    }
    
    function handleSend(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused
    {
        (uint tokenId, uint lockedAmount, uint lockedEnd) = abi.decode(payload, (uint, uint, uint));
        
        uint currentLockedAmount = veArc.locked__amount(tokenId);
        require(currentLockedAmount == lockedAmount, 'Locked amount for veArc is invalid');
        
        uint currentLockedEnd = veArc.locked__end(tokenId);
        require(currentLockedEnd == lockedEnd, 'Locked end for veArc is invalid');
        
        uint blockTimestamp = block.timestamp;
        uint lockDuration = lockedEnd - blockTimestamp;
        require(lockDuration > 0, 'veArc cannot be expired');
        
        uint unlockTime = (blockTimestamp + lockDuration) / WEEK * WEEK; // Locktime is rounded down to weeks
        require(unlockTime > blockTimestamp, 'Lock cannot expire soon');
        require(unlockTime <= blockTimestamp + MAXTIME, 'Cannot be locked for more than 4 years');
        
        veArc.safeTransferFrom(target, address(this), tokenId);
        veArc.burn(tokenId);
    }
    
    function handleReceive(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused
    {
        (uint tokenId, uint lockedAmount, uint lockedEnd) = abi.decode(payload, (uint, uint, uint));
        
        uint blockTimestamp = block.timestamp;
        uint newLockDuration = lockedEnd - blockTimestamp;
        
        IArc arc = rainbowRoad.arc();
        
        arc.mint(address(this), lockedAmount);
        arc.approve(address(veArc), lockedAmount);
        uint newTokenId = veArc.create_lock_for(lockedAmount, newLockDuration, target);
        emit VeArcMinted(target, tokenId, newTokenId, lockedAmount, lockedEnd, newLockDuration + blockTimestamp);
    }
    
    function onERC721Received(address operator, address from, uint tokenId, bytes calldata data) external returns (bytes4) {
        emit VeArcReceived(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }
}
