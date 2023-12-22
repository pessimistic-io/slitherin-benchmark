// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

import {MerkleDistributor} from "./MerkleDistributor.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {Pausable} from "./Pausable.sol";
error EndTimeInPast();
error ClaimWindowFinished();
error NoWithdrawDuringClaim();

contract PlutusJonesMerkleDistributorWithDeadline is MerkleDistributor, Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint256 public immutable endTime;

    constructor(address token_, bytes32 merkleRoot_, uint256 endTime_) MerkleDistributor(token_, merkleRoot_) {
        if (endTime_ <= block.timestamp) revert EndTimeInPast();
        endTime = endTime_;
        _pause();
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) public override whenNotPaused {
        if (block.timestamp > endTime) revert ClaimWindowFinished();
        super.claim(index, account, amount, merkleProof);
    }

    function withdraw() external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function setPause(bool _isPaused) external onlyOwner {
        if (_isPaused) {
            _pause();
        } else {
            _unpause();
        }
    }
}

