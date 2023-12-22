// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./IOnboardingRequest.sol";

contract OnboardingRequest is IOnboardingRequest {
    // gov => index
    mapping(address => uint128) public nextIndex;
    // gov => index => Request
    mapping(address => mapping(uint128 => Request)) public requests;

    /**
     *  @inheritdoc IOnboardingRequest
     */
    function addRequest(
        address _gov,
        address _timelock,
        address _tokenApproved,
        uint256 _amountApproved,
        uint256 _requestedMint
    ) public override {
        require(
            IERC20(_tokenApproved).allowance(msg.sender, _timelock) >=
                _amountApproved,
            "Insuficient approval to add request"
        );

        Request memory newRequest = Request({
            sender: msg.sender,
            timelock: _timelock,
            tokenApproved: _tokenApproved,
            amountApproved: _amountApproved,
            requestedMint: _requestedMint,
            timestamp: block.timestamp
        });

        uint128 index = nextIndex[_gov];
        requests[_gov][index] = newRequest;
        nextIndex[_gov]++;

        emit AddedRequest(msg.sender, _gov, index);
    }


    /**
     *  @inheritdoc IOnboardingRequest
     */
    function removeRequest(address _gov, uint128 _index) public override {
        Request memory request = requests[_gov][_index];
        require(request.sender != address(0), "Request does not exist");
        require(
            request.timelock == msg.sender,
            "Only the timelock can delete a request"
        );
        delete requests[_gov][_index];
        emit RemovedRequest(_gov, _index);
    }
}

