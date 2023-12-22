// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IVRFStorage.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./IVRFClient.sol";
import "./Random.sol";

abstract contract VRF is IVRFStorage, IVRFClient {
    error OnlyCoordinatorCanFulfill(address have, address want);
    error UnknownRequestId(uint requestId);

    function _randomBuyResponseHandler(IdType firstId, uint16 count, Random.Seed memory random) internal virtual;
    function _randomClaimResponseHandler(IdType id, Random.Seed memory random) internal virtual;

    /**
     * @dev Request a random number for buy action.
     */
    function _requestBuyRandom(IdType id, uint16 count) internal {
        uint requestId = _createNewRequest();
        _requestMap(requestId, BUY_REQUEST, id, count);
    }

    /**
     * @dev Request a random number for claim action.
     */
    function _requestClaimRandom(IdType id) internal {
        uint requestId = _createNewRequest();
        _requestMap(requestId, CLAIM_REQUEST, id, 1);
    }

    /**
     * @dev Cancel existing request and do it again.
     * @notice VRF request is not canceled, but the corresponding record in the map is deleted
     *          it means response will not be handled.
     */
    function _repeatRequest(uint requestId) internal {
        VRFRequest storage request = _requestMap(requestId);
        if (request.count == 0) {
            revert UnknownRequestId(requestId);
        }
        uint newRequestId = _createNewRequest();
        VRFRequest storage newRequest = _requestMap(newRequestId);
        // copy the whole request
        newRequest.rarity = request.rarity;
        newRequest.count = request.count;
        newRequest.firstTokenId = request.firstTokenId;
        newRequest.requestType = request.requestType;

        _delRequest(requestId);
    }

    /**
     * @param requestId The Id initially returned by requestRandomness
     * @param randomWords the VRF output expanded to the requested number of words
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        if (msg.sender != _vrfCoordinator()) {
            revert OnlyCoordinatorCanFulfill(msg.sender, _vrfCoordinator());
        }
        VRFRequest storage request = _requestMap(requestId);
        if (request.count == 0) {
            revert UnknownRequestId(requestId);
        }

        Random.Seed memory seed = Random.Seed(randomWords[0], 0);
        uint16 requestCount = request.count;

        if (request.requestType == BUY_REQUEST) {
            IdType firstTokenId = request.firstTokenId;
            _delRequest(requestId);
            _randomBuyResponseHandler(firstTokenId, requestCount, seed);
            return;
        }

        if (request.requestType == CLAIM_REQUEST) {
            IdType lockedId = request.firstTokenId;
            _delRequest(requestId);
            _randomClaimResponseHandler(lockedId, seed);
            return;
        }
    }

    function _createNewRequest() private returns(uint) {
        return VRFCoordinatorV2Interface(_vrfCoordinator())
            .requestRandomWords(
            _keyHash(),
            _subscriptionId(),
            _requestConfirmations(),
            _callbackGasLimit(),
            1
        );
    }
}

