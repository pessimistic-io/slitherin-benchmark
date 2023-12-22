// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IVRFCoordinatorV2} from "./IVRFCoordinatorV2.sol";

import {VRFCoordinatorV2Interface} from "./VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "./VRFConsumerBaseV2.sol";

import {Ownable} from "./Ownable.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

import {IEACAggregatorProxy} from "./IEACAggregatorProxy.sol";

abstract contract BaseVRFConsumer is VRFConsumerBaseV2, Ownable {

    using EnumerableSet for EnumerableSet.UintSet;

    event RequestFulfilled(address user_, uint256 requestId, uint256 randomWord, uint8 fulfilled);

    struct RequestInfo {
        address user;
        uint256 randomWord;
        uint8 fulfilled;
    }

    struct RequestResult {
        uint256 requestId;
        address user;
        uint256 randomWord;
        uint8 fulfilled;
    }

    mapping(address => uint256) internal _userLatestRequestId;

    mapping(address => EnumerableSet.UintSet) internal _userRequestIds;

    mapping(address => EnumerableSet.UintSet) private _userUnFulfilledRequestIds;

    mapping(uint256 => RequestInfo) internal _requestIdRequestInfo;

    address public immutable priceFeedContractAddress;

    address public immutable coordinator;

    uint64 public immutable subscriptionId;

    bytes32 _keyHash;

    constructor(address priceFeedContractAddress_, address vrfCoordinator_, bytes32 keyHash_, uint64 subscriptionId_)
        VRFConsumerBaseV2(vrfCoordinator_){
        priceFeedContractAddress = priceFeedContractAddress_;
        coordinator = vrfCoordinator_;
        _keyHash = keyHash_;
        subscriptionId = subscriptionId_;
    }

    // internal

    function beforeRequest(address user_) internal returns (uint256 requestId_) {
        require(msg.value > 0 && msg.value >= estimateSpentGas(tx.gasprice), "BaseVRFConsumer: gas fee insufficient");
        requestId_ = VRFCoordinatorV2Interface(coordinator).requestRandomWords(
            _keyHash,
            subscriptionId,
            3,
            estimateGasLimit(),
            1
        );
        _requestIdRequestInfo[requestId_] = RequestInfo(user_, 0, 0);
        if (!_userRequestIds[user_].contains(requestId_)) {
            _userRequestIds[user_].add(requestId_);
            _userLatestRequestId[user_] = requestId_;
        }
        return requestId_;
    }

    function beforeFulfill(uint256 requestId_, uint256 randomWord_) internal returns (RequestInfo storage requestInfo_){
        requestInfo_ = _requestIdRequestInfo[requestId_];
        require(requestInfo_.user != address(0), "BaseVRFConsumer: request not found");
        requestInfo_.randomWord = randomWord_;
        return requestInfo_;
    }

    function afterFulfill(uint256 requestId_) internal {
        RequestInfo memory requestInfo_ = _requestIdRequestInfo[requestId_];
        address user_ = requestInfo_.user;
        EnumerableSet.UintSet storage uintSet_ = _userUnFulfilledRequestIds[user_];
        if (requestInfo_.fulfilled == 1 && !uintSet_.contains(requestId_)) {
            uintSet_.add(requestId_);
        } else if (requestInfo_.fulfilled == 2 && uintSet_.contains(requestId_)) {
            uintSet_.remove(requestId_);
        }
        emit RequestFulfilled(requestInfo_.user, requestId_, requestInfo_.randomWord, requestInfo_.fulfilled);
    }

    // external

    function viewRequestInfo(uint256 requestId_) external view returns (RequestInfo memory){
        return _requestIdRequestInfo[requestId_];
    }

    function viewRequestResults(address user_, uint256 startIndex_, uint256 endIndex_) external view returns (RequestResult[] memory requestResultArr){
        if (startIndex_ >= 0 && endIndex_ >= startIndex_) {
            uint256 len = endIndex_ + 1 - startIndex_;
            uint256 total = _userRequestIds[user_].length();
            uint256 arrayLen = len > total ? total : len;
            requestResultArr = new RequestResult[](arrayLen);
            uint256 arrayIndex_ = 0;
            for (uint256 index_ = startIndex_; index_ < ((endIndex_ > total) ? total : endIndex_);) {
                uint256 requestId_ = _userRequestIds[user_].at(index_);
                RequestInfo memory requestInfo_ = _requestIdRequestInfo[requestId_];
                requestResultArr[arrayIndex_] = RequestResult(
                    requestId_,
                    requestInfo_.user,
                    requestInfo_.randomWord,
                    requestInfo_.fulfilled
                );
                unchecked{++index_; ++arrayIndex_;}
            }
        }
        return requestResultArr;
    }

    function viewUnFulfilledRequestIds(address user_, uint256 startIndex_, uint256 endIndex_) external view returns (uint256[] memory requestIdArr){
        if (startIndex_ >= 0 && endIndex_ >= startIndex_) {
            uint256 len = endIndex_ + 1 - startIndex_;
            uint256 total = _userUnFulfilledRequestIds[user_].length();
            uint256 arrayLen = len > total ? total : len;
            requestIdArr = new uint256[](arrayLen);
            uint256 arrayIndex_ = 0;
            for (uint256 index_ = startIndex_; index_ < ((endIndex_ > total) ? total : endIndex_);) {
                requestIdArr[arrayIndex_] = _userUnFulfilledRequestIds[user_].at(index_);
                unchecked{++index_; ++arrayIndex_;}
            }
        }
        return requestIdArr;
    }

    function viewLatestRequestId(address user_) external view returns (uint256){
        return _userLatestRequestId[user_];
    }

    function estimateSpentLink(uint256 gasPriceWei_) external view returns (uint256){
        (,int256 answer,,,) = IEACAggregatorProxy(priceFeedContractAddress).latestRoundData();
        return gasPriceWei_ * estimateGasLimit() * 1e18 / uint256(answer);
    }

    function withdrawFee() external payable onlyOwner {
        if (address(this).balance > 0) {
            (bool success, ) = _msgSender().call{value: address(this).balance}(new bytes(0));
            require(success, 'safe transfer ETH');
        }
    }

    // public

    function estimateSpentGas(uint256 gasPriceWei_) public view returns (uint256){
        return estimateGasLimit() * gasPriceWei_;
    }

    function estimateGasLimit() public view returns (uint32){
        (,uint32 maxGasLimit_,,) = IVRFCoordinatorV2(coordinator).getConfig();
        return maxGasLimit_;
    }

}

