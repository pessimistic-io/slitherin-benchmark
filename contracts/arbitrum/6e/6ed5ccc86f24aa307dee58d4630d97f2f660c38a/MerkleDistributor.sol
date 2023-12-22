// SPDX-License-Identifier: MIT

/**
 * Created on 2023-01-24 05:55
 * @Summary A smart contract that distributes a balance of tokens according to a merkle root.
 * @title MerkleDistributor
 * @author: Overlay - c-n-o-t-e
 */
 
pragma solidity =0.8.17;

import {Ownable} from "./Ownable.sol";
import {IMerkleDistributor} from "./IMerkleDistributor.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";


error InvalidProof();
error EndTimeInPast();
error AlreadyClaimed();
error ClaimWindowFinished();
error NoWithdrawDuringClaim();

contract MerkleDistributor is IMerkleDistributor, Ownable {
    using SafeERC20 for IERC20;

    uint256 public immutable endTime;
    address public immutable override token;
    bytes32 public immutable override merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(address token_, bytes32 merkleRoot_, uint256 endTime_) {
        if (endTime_ <= block.timestamp) revert EndTimeInPast();
        token = token_;

        endTime = endTime_;
        merkleRoot = merkleRoot_;
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;

        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);

        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof)
        public
        virtual
        override
    {
        if (block.timestamp > endTime) revert ClaimWindowFinished();
        if (isClaimed(index)) revert AlreadyClaimed();

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        if (!MerkleProof.verify(merkleProof, merkleRoot, node)) revert InvalidProof();

        // Mark it claimed and send the token.
        _setClaimed(index);
        IERC20(token).safeTransfer(account, amount);

        emit Claimed(index, account, amount);
    }

    function withdraw() external virtual override onlyOwner {
        if (block.timestamp < endTime) revert NoWithdrawDuringClaim();
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        emit Withdraw(msg.sender, IERC20(token).balanceOf(owner()));
    }
}

