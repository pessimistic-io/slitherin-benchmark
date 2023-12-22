// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./MathUpgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

import "./console.sol";

contract Sip2Earn is OwnableUpgradeable {
    using MathUpgradeable for uint256;

    address public keeper;

    struct ClaimRequest {
        address claimer;
        uint256 timestamp;
        uint256 id;
        uint256 tier;
        bool fulfilled;
        bool cancelled;
    }

    mapping(address => mapping(uint256 => ClaimRequest)) private claimRequests;
    mapping(address => uint256) public claimCount;
    mapping(address => bool) public isClaimer;
    address[] public claimers;

    event KeeperUpdated(address _keeper);
    event ClaimRequested(address _claimer, uint256 _timestamp, uint256 _id);
    event ClaimFulfilled(address _claimer, uint256 _id);

    function initialize() external initializer {
        __Ownable_init();
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper, "Caller is not the keeper");
        _;
    }

    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0), "Keeper address cannot be 0");
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function requestClaim(uint256 _tier) external {
        require(_tier == 1 || _tier == 2 || _tier == 3, "Invalid tier");
        
        if (!isClaimer[msg.sender]) {
            isClaimer[msg.sender] = true;
            claimers.push(msg.sender);
        }

        uint256 request = claimCount[msg.sender];
        ClaimRequest storage cr = claimRequests[msg.sender][request];
        cr.claimer = msg.sender;
        cr.timestamp = block.timestamp;
        cr.id = request;
        cr.tier = _tier;

        claimCount[msg.sender] ++;

        emit ClaimRequested(msg.sender, block.timestamp, request);
    }

    function fulfillClaimRequest(
        address _claimer,
        uint256 _id,
        uint256 _amount,
        bool _success,
        address _rewardToken) external onlyKeeper {
        ClaimRequest storage cr = claimRequests[_claimer][_id];
        require(cr.claimer != address(0), "Claim request does not exist");
        require(!cr.fulfilled, "Claim request already fulfilled");
        require(!cr.cancelled, "Claim request already cancelled");

        if (_success) {
            cr.fulfilled = true;
            IERC20Upgradeable(_rewardToken).transfer(_claimer, _amount);
        } else {
            cr.cancelled = true;
        }
        
        emit ClaimFulfilled(_claimer, _id);
    }

    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20Upgradeable(_token).transfer(msg.sender, _amount);
    }

}

