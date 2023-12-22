//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { Referrers } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeReferral } from "./IPepeReferral.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeReferral is IPepeReferral, Ownable2Step {
    using SafeERC20 for IERC20;
    IERC20 public immutable usdcToken;

    uint256 public referEpochId;

    mapping(uint256 epochId => Referrers) public refers; //epochId => referrers
    mapping(uint256 epochId => uint256) public unclaimedAllocation;
    mapping(uint256 epochId => mapping(address => uint256 index)) public referrerIndex;
    mapping(uint256 epochId => bool) public claimEnabled;

    event ReferrersAdded(
        uint256 indexed epochId,
        uint256 indexed totalAllocation,
        address[] referrers,
        uint256[] allocations
    );
    event UsdcClaimed(uint256 indexed epochId, address indexed referrer, uint256 indexed amount);
    event ClaimedForAll(address indexed referrer);

    constructor(address usdcToken_) {
        usdcToken = IERC20(usdcToken_);
    }

    ///@notice admin must transfer usdc to this contract before calling this function.
    ///@param referrers array of users who referred others to the platform.
    ///@param allocations array of allocations for each referrer.
    function addReferrers(address[] calldata referrers, uint256[] calldata allocations) external override onlyOwner {
        require(referrers.length == allocations.length, "PepeReferral: Invalid input");

        uint256 referrersLength = referrers.length;
        uint256 epochAllocation;
        uint256 id = ++referEpochId;

        uint256 i;
        for (; i < referrersLength; ) {
            require(referrers[i] != address(0), "PepeReferral: Invalid referrer");
            require(allocations[i] != 0, "PepeReferral: Invalid allocation");

            epochAllocation += allocations[i];
            referrerIndex[referEpochId][referrers[i]] = i;

            unchecked {
                ++i;
            }
        }

        uint256 contractBalance = usdcToken.balanceOf(address(this));
        uint256 j;
        for (; j <= referEpochId; ) {
            contractBalance -= unclaimedAllocation[j];
            unchecked {
                ++j;
            }
        }

        //solhint-disable-next-line reason-string
        require(contractBalance >= epochAllocation, "PepeReferral: Insufficient balance");

        refers[id] = Referrers(id, referrers, allocations);
        unclaimedAllocation[id] = epochAllocation;

        emit ReferrersAdded(id, epochAllocation, referrers, allocations);
    }

    function enableClaim(uint256 epochId) external override onlyOwner {
        claimEnabled[epochId] = true;
    }

    function disableClaim(uint256 epochId) external override onlyOwner {
        claimEnabled[epochId] = false;
    }

    function claimUsdc(uint256 epochId) public override {
        //solhint-disable-next-line reason-string
        require(claimEnabled[epochId], "PepeReferral: Epoch claim not enabled");
        Referrers memory referrer_ = refers[epochId];

        uint256 userIndex = referrerIndex[epochId][msg.sender];

        if (referrer_.referrers[userIndex] == msg.sender) {
            uint256 allocation = referrer_.allocations[userIndex];

            if (allocation != 0) {
                refers[epochId].allocations[userIndex] = 0;

                unclaimedAllocation[epochId] -= allocation;

                usdcToken.safeTransfer(msg.sender, allocation);

                emit UsdcClaimed(epochId, msg.sender, allocation);
            }
        }
    }

    function claimAll() external override {
        uint256 epochId = referEpochId;

        uint256 i = 1;
        for (; i <= epochId; ) {
            if (claimEnabled[i]) {
                claimUsdc(i);
            }
            unchecked {
                ++i;
            }
        }

        emit ClaimedForAll(msg.sender);
    }

    function retrieve(address _token) external override onlyOwner {
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "Retrieval Failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    function getClaimableUsdc(uint256 epochId, address referrer) public view override returns (uint256) {
        Referrers memory referrer_ = refers[epochId];

        uint256 userIndex = referrerIndex[epochId][referrer];

        if (referrer_.referrers[userIndex] == referrer) {
            return referrer_.allocations[userIndex];
        }

        return 0;
    }

    function getClaimableUsdc(address referrer) external view override returns (uint256) {
        uint256 epochId = referEpochId;

        uint256 i = 1;
        uint256 claimableUsdc;
        for (; i <= epochId; ) {
            claimableUsdc += getClaimableUsdc(i, referrer);
            unchecked {
                ++i;
            }
        }

        return claimableUsdc;
    }

    function getReferrers(uint256 epochId) external view override returns (address[] memory) {
        return refers[epochId].referrers;
    }

    function getAllocations(uint256 epochId) external view override returns (uint256[] memory) {
        return refers[epochId].allocations;
    }

    function getUnclaimedAllocation(uint256 epochId) external view override returns (uint256) {
        return unclaimedAllocation[epochId];
    }

    function isClaimEnabled(uint256 epochId) external view override returns (bool) {
        return claimEnabled[epochId];
    }

    function getReferrerIndex(uint256 epochId, address referrer) external view override returns (uint256) {
        uint256 userIndex = referrerIndex[epochId][referrer];
        if (userIndex == 0 && refers[epochId].referrers[userIndex] != referrer) revert("referral not found");
        return userIndex;
    }
}

