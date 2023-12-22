// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./SafeERC20.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

contract JITCouponAirdrop is Ownable {
    using SafeERC20 for IERC20;

    bool public isClaimEnabled;
    
    // max claim addresses: 1000
    uint256 public constant maxClaimAddressCount = 1000;
    uint256 private claimedAddressCount;

    address public immutable jitCouponToken;
    bytes32 public immutable merkleRoot;

    mapping(address => bool) private hasClaimed;

    event Claimed(address indexed claimer, uint256 amount);

    constructor(address _jitCouponToken, bytes32 _merkleRoot) Ownable() {
        jitCouponToken = _jitCouponToken;
        merkleRoot = _merkleRoot;
    }

    function claim(uint256 amount, bytes32[] calldata merkleProof) external {
        require(isClaimEnabled, "Claim is not activated.");
        require(!hasClaimed[msg.sender], "Already claimed.");
        require(claimedAddressCount < maxClaimAddressCount, "Airdrop is over.");
        bytes32 node = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "Invalid proof.");

        hasClaimed[msg.sender] = true;
        IERC20(jitCouponToken).safeTransfer(msg.sender, amount);

        claimedAddressCount ++;

        emit Claimed(msg.sender, amount);
    }

    function toggleClaim() external onlyOwner {
        isClaimEnabled = !isClaimEnabled;
    }

    function isClaimed(address _claimer) external view returns (bool) {
        return hasClaimed[_claimer];
    }

    function getClaimedAddressCount() external view returns (uint256) {
        return claimedAddressCount;
    }

    // ==== optional functions ====

    function emergencyWithdrawEther() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // emergency withdraw any erc20 token
    function emergencyWithdrawToken(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(owner(), balance);
    }

    function burnUnclaimed() external onlyOwner {
        require(!isClaimEnabled, "Claim is still activated.");
        uint256 balance = IERC20(jitCouponToken).balanceOf(address(this));
        IERC20(jitCouponToken).safeTransfer(address(0), balance);
    }
}

