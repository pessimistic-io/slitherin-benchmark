// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {BatchAuction} from "./BatchAuction.sol";
import {IERC20} from "./IERC20.sol";

contract LvlBatchAuction is BatchAuction {
    uint64 public constant MAX_VESTING_DURATION = 7 days;
    uint64 public vestingDuration;
    uint64 public vestingStart;

    constructor(
        address _auctionToken,
        address _payToken,
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _minimumCeilingPrice,
        uint128 _ceilingPrice,
        uint128 _minimumPrice,
        address _admin,
        address _treasury,
        uint64 _vestingDuration
    )
        BatchAuction(
            _auctionToken,
            _payToken,
            _totalTokens,
            _startTime,
            _endTime,
            _minimumCeilingPrice,
            _ceilingPrice,
            _minimumPrice,
            _admin,
            _treasury
        )
    {
        require(_vestingDuration <= MAX_VESTING_DURATION, "> MAX_VESTING_DURATION");
        vestingDuration = _vestingDuration;
    }

    function tokensClaimableWithoutVesting(address _user) public view returns (uint256 _claimerCommitment) {
        if (commitments[_user] == 0) {
            return 0;
        }

        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        _claimerCommitment = commitments[_user] * totalTokens / commitmentsTotal;
        _claimerCommitment = _claimerCommitment - claimed[_user];
        if (_claimerCommitment > unclaimedTokens) {
            _claimerCommitment = unclaimedTokens;
        }
    }

    function tokensClaimable(address _user) public view override returns (uint256 _claimerCommitment) {
        if (vestingDuration == 0) {
            return tokensClaimableWithoutVesting(_user);
        }

        if (commitments[_user] == 0) {
            return 0;
        }

        if (vestingStart == 0) {
            return 0;
        }

        if (block.timestamp >= (vestingStart + vestingDuration)) {
            _claimerCommitment = commitments[_user] * totalTokens / commitmentsTotal;
        } else {
            uint256 _time = block.timestamp - vestingStart;
            _claimerCommitment = _time * commitments[_user] * totalTokens / commitmentsTotal / vestingDuration;
        }

        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        _claimerCommitment -= claimed[_user];
        if (_claimerCommitment > unclaimedTokens) {
            _claimerCommitment = unclaimedTokens;
        }
    }

    function _finalizeSuccessfulAuctionFund() internal override {
        _safeTransferToken(payToken, auctionTreasury, commitmentsTotal);
        if (vestingDuration > 0) {
            vestingStart = uint64(block.timestamp);
            emit VestingStarted(vestingStart);
        }
    }

    // EVENTS
    event VestingStarted(uint64 timestamp);
}

