// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProof.sol";

contract TokenClaim is Ownable {
    struct ClaimEvent {
        address token;
        uint256 startTime;
        uint256 endTime;
        bytes32 merkleRoot;
        mapping(address => bool) claimedAddresses;
    }

    uint256 public eventIndex;
    mapping(uint256 => ClaimEvent) public claimEvents;

    event EventCreated(
        uint256 indexed index,
        address indexed token,
        uint256 startTime,
        uint256 endTime,
        bytes32 merkleRoot
    );
    event Claimed(uint256 indexed index, address indexed claimer, uint256 indexed amount);

    function setupEvent(
        address _token,
        uint256 _endTimeFromNow,
        bytes32 _merkleRoot
    ) public onlyOwner {
        setupEvent(_token, block.timestamp, block.timestamp + _endTimeFromNow, _merkleRoot);
    }

    function setupEvent(
        address _token,
        uint256 _startTime,
        uint256 _endTime,
        bytes32 _merkleRoot
    ) public onlyOwner {
        require(_startTime <= _endTime, "TokenClaim: Invalid Time");
        claimEvents[eventIndex].token = _token;
        claimEvents[eventIndex].startTime = _startTime;
        claimEvents[eventIndex].endTime = _endTime;
        claimEvents[eventIndex].merkleRoot = _merkleRoot;
        emit EventCreated(eventIndex, _token, _startTime, _endTime, _merkleRoot);
        ++eventIndex;
    }

    function updateMerkleRoot(uint256 _eventIndex, bytes32 _merkleRoot) public onlyOwner {
        claimEvents[_eventIndex].merkleRoot = _merkleRoot;
    }

    function withdrawToken(address _token, uint256 _amount) public onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function isClaimed(uint256 _eventIndex, address _address) public view returns (bool) {
        return claimEvents[_eventIndex].claimedAddresses[_address];
    }

    function claim(
        uint256 _eventIndex,
        bytes32[] calldata _merkleProof,
        address _claimer,
        uint256 _amount
    ) public {
        ClaimEvent storage claimEvent = claimEvents[_eventIndex];
        require(block.timestamp >= claimEvent.startTime, "TokenClaim: Have not started!");
        require(block.timestamp <= claimEvent.endTime, "TokenClaim: Expired!");
        require(!claimEvent.claimedAddresses[_claimer], "TokenClaim: Already claimed!");

        bytes32 leaf = keccak256(abi.encodePacked(_claimer, _amount));
        require(MerkleProof.verifyCalldata(_merkleProof, claimEvent.merkleRoot, leaf), "TokenClaim: Unable to verify.");

        claimEvent.claimedAddresses[_claimer] = true;
        require(IERC20(claimEvent.token).transfer(_claimer, _amount), "TokenClaim: trasnfer failed.");
        emit Claimed(_eventIndex, _claimer, _amount);
    }
}

