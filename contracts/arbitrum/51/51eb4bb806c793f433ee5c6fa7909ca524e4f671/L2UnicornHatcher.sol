// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IAccessControl} from "./IAccessControl.sol";

import {IL2Unicorn} from "./IL2Unicorn.sol";
import {IL2UnicornRule} from "./IL2UnicornRule.sol";

import {Pausable} from "./Pausable.sol";

import {BaseVRFConsumer} from "./BaseVRFConsumer.sol";
import {BaseMaximum} from "./BaseMaximum.sol";
import {BaseL2} from "./BaseL2.sol";
import {BaseL2Unicorn} from "./BaseL2Unicorn.sol";
import {BaseL2UnicornRule} from "./BaseL2UnicornRule.sol";
import {BaseRecipient} from "./BaseRecipient.sol";
import {BaseCommissionManager} from "./BaseCommissionManager.sol";

import {L2UnicornHatcherPermit} from "./L2UnicornHatcherPermit.sol";

/**
 * @notice Unicorn Hatcher
 */
contract L2UnicornHatcher is L2UnicornHatcherPermit, BaseVRFConsumer, BaseMaximum, BaseL2, BaseL2Unicorn, BaseL2UnicornRule, BaseRecipient, BaseCommissionManager, Pausable {

    struct HatchResult {
        address user;
        uint256 requestId;
        uint256 randomWord;
        uint8 eSeries;
        uint32 numberIndex;
        uint256 randomNumber;
        uint8 level;
    }

    event HatchCallback (
        address indexed user,
        uint256 requestId,
        uint256 randomWord,
        uint8 eSeries,
        uint32 numberIndex,
        uint256 randomNumber,
        uint8 level,
        uint256 tokenId,
        address collection
    );

    event CommissionPayment(
        address indexed user,
        address indexed recipient,
        address erc20,
        uint256 amount
    );

    mapping(address => uint256) private _userMaxNonces;

    mapping(uint8 => uint256) private _costAmount;

    mapping(uint256 => uint32) private _requestIdHatchCount;

    mapping(uint256 => uint8) private _requestIdESeries;

    constructor(address l2Unicorn_, address l2UnicornRule_, address l2_, address recipient_, address authorizer_, address priceFeedContractAddress_, address vrfCoordinator_, bytes32 keyHash_, uint64 vrfSubscriptionId_)
        BaseVRFConsumer(priceFeedContractAddress_, vrfCoordinator_, keyHash_, vrfSubscriptionId_)
        BaseMaximum(150)
        BaseL2Unicorn(l2Unicorn_)
        BaseL2UnicornRule(l2UnicornRule_)
        BaseL2(l2_)
        BaseRecipient(recipient_)
        L2UnicornHatcherPermit(authorizer_){
        _costAmount[1] = 100e18;
        _costAmount[2] = 1000e18;
    }

    function hatchE0(uint256 deadline, uint8 v, bytes32 r, bytes32 s) payable external whenNotPaused {
        uint8 eSeries_ = 0;
        require(_nonces[_msgSender()] <= _userMaxNonces[_msgSender()] || _nonces[_msgSender()] == 0, "L2UnicornHatcher: user already hatch E0 series");
        permit(_msgSender(), eSeries_, deadline, v, r, s);
        require(IAccessControl(l2Unicorn).hasRole(0xaeaef46186eb59f884e36929b6d682a6ae35e1e43d8f05f058dcefb92b601461, address(this)), "L2UnicornHatcher: l2 unicorn access denied");
        require(!Pausable(l2Unicorn).paused(), "L2UnicornHatcher: l2 unicorn already paused");
        //
        uint256 requestId_ = beforeRequest(_msgSender());
        _requestIdHatchCount[requestId_] = 1;
        _requestIdESeries[requestId_] = eSeries_;
    }

    function hatchE1E2(uint32 hatchCount_, uint8 eSeries_, address commissionRecipient_) payable external whenNotPaused {
        require(hatchCount_ > 0 && hatchCount_ <= maximum, "L2UnicornHatcher: exceed maximum");
        require(eSeries_ == 1 || eSeries_ == 2, "L2UnicornHatcher: e series invalid");
        require(IAccessControl(l2Unicorn).hasRole(0xaeaef46186eb59f884e36929b6d682a6ae35e1e43d8f05f058dcefb92b601461, address(this)), "L2UnicornHatcher: access denied");
        require(!Pausable(l2Unicorn).paused(), "L2UnicornHatcher: l2 unicorn already paused");
        require(_costAmount[eSeries_] > 0, "L2UnicornHatcher: cost amount is zero");
        //
        uint256 totalCostAmount_ = hatchCount_ * _costAmount[eSeries_];
        if(commissionRecipient_ != address(0)){
            require(fraction <= denominator - slippage, "L2UnicornHatcher: commission exceeds slippage");
            uint256 commissionAmount_ = totalCostAmount_ / denominator * fraction;
            require(IERC20(l2).transferFrom(_msgSender(), commissionRecipient_, commissionAmount_), "L2UnicornHatcher: transfer failure");
            totalCostAmount_ -= commissionAmount_;
            emit CommissionPayment(_msgSender(), commissionRecipient_, l2, commissionAmount_);
        }
        require(IERC20(l2).transferFrom(_msgSender(), recipient, totalCostAmount_), "L2UnicornHatcher: transfer failure");
        //
        uint256 requestId_ = beforeRequest(_msgSender());
        _requestIdHatchCount[requestId_] = hatchCount_;
        _requestIdESeries[requestId_] = eSeries_;
    }

    /**
     * @notice Callback
     */
    function fulfillRandomWords(uint256 requestId_, uint256[] memory randomWords_) override internal {
        require(randomWords_.length > 0, "L2UnicornHatcher: random words is empty");
        uint256 randomWord_ = randomWords_[0];
        RequestInfo storage requestInfo_ = beforeFulfill(requestId_, randomWord_);
        bool immediately_ = _requestIdHatchCount[requestId_] <= 10;
        if (immediately_) {
            requestInfo_.fulfilled = 1;
        }
        _fulfillByRequestId(requestId_, immediately_);
    }

    /**
     * @notice User Fulfill
     */
    function userFulfill(uint256[] memory requestIds_) external {
        require(requestIds_.length > 0, "L2UnicornHatcher: request id is empty");
        uint256 length_ = requestIds_.length;
        for (uint8 index_ = 0; index_ < length_;) {
            _fulfillByRequestId(requestIds_[index_], true);
            unchecked{++index_;}
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setCostAmount(uint8 eSeries_, uint256 costAmount_) external onlyOwner {
        require(eSeries_ == 0 || eSeries_ == 1, "L2UnicornHatcher: e series invalid");
        _costAmount[eSeries_] = costAmount_;
    }

    function getCostAmount(uint8 eSeries_) view external returns (uint256){
        return _costAmount[eSeries_];
    }

    function setUserMaxNonces(address[] calldata userList_, uint256[] calldata noncesList_) external onlyOwner {
        uint256 length = userList_.length;
        require(noncesList_.length == length, "L2UnicornHatcher: invalid parameter");
        for (uint256 index_ = 0; index_ < length;) {
            require(noncesList_[index_] > _nonces[userList_[index_]], "L2UnicornHatcher: invalid user nonces");
            _userMaxNonces[userList_[index_]] = noncesList_[index_];
            unchecked{++index_;}
        }
    }

    function getHatchRandomNumber(uint8 eSeries_, uint256 randomWord_, uint256 numberIndex_) public view returns (uint256){
        if (eSeries_ == 0) {
            return randomWord_ % IL2UnicornRule(l2UnicornRule).modNumber();
        } else {
            bytes32 newRandomWord_ = keccak256(abi.encodePacked(randomWord_, numberIndex_));
            return uint256(newRandomWord_) % IL2UnicornRule(l2UnicornRule).modNumber();
        }
    }

    function viewUserMaxNonces(address user_) external view returns (uint256){
        return _userMaxNonces[user_];
    }

    function viewHatchResults(uint256 requestId_) external view returns (HatchResult[] memory hatchResults){
        uint32 hatchCount_ = _requestIdHatchCount[requestId_];
        uint8 eSeries_ = _requestIdESeries[requestId_];
        RequestInfo memory requestInfo_ = _requestIdRequestInfo[requestId_];
        //
        hatchResults = new HatchResult[](hatchCount_);
        for (uint32 numberIndex_ = 0; numberIndex_ < hatchCount_;) {
            (uint256 randomNumber_, IL2UnicornRule.HatchRule memory hatchRule_) = _getRandomNumberAndHatchRule(requestInfo_.randomWord, eSeries_, numberIndex_);
            hatchResults[numberIndex_] = HatchResult(
                requestInfo_.user,
                requestId_,
                requestInfo_.randomWord,
                eSeries_,
                numberIndex_,
                randomNumber_,
                hatchRule_.level
            );
            unchecked{++numberIndex_;}
        }
        return hatchResults;
    }

    function _getRandomNumberAndHatchRule(uint256 randomWord_, uint8 eSeries_, uint256 numberIndex_) private view returns (uint256 randomNumber_, IL2UnicornRule.HatchRule memory hatchRule_){
        randomNumber_ = getHatchRandomNumber(eSeries_, randomWord_, numberIndex_);
        hatchRule_ = IL2UnicornRule(l2UnicornRule).getHatchRuleByESeriesRandomNum(eSeries_, randomNumber_);
    }

    function _fulfillByRequestId(uint256 requestId_, bool immediately_) private {
        RequestInfo storage requestInfo_ = _requestIdRequestInfo[requestId_];
        if (immediately_) {
            uint8 eSeries_ = _requestIdESeries[requestId_];
            _mint(requestInfo_.user, requestId_, requestInfo_.randomWord, eSeries_);
            require(requestInfo_.fulfilled == 1, "L2UnicornHatcher: request id fulfilled error");
            requestInfo_.fulfilled = 2;
        } else {
            require(requestInfo_.fulfilled == 0, "L2UnicornHatcher: request id fulfilled error");
            requestInfo_.fulfilled = 1;
        }
        afterFulfill(requestId_);
    }

    function _mint(address user_, uint256 requestId_, uint256 randomWord_, uint8 eSeries_) private {
        uint32 hatchCount_ = _requestIdHatchCount[requestId_];
        for (uint32 numberIndex_ = 0; numberIndex_ < hatchCount_;) {
            (uint256 randomNumber_, IL2UnicornRule.HatchRule memory hatchRule_) = _getRandomNumberAndHatchRule(randomWord_, eSeries_, numberIndex_);
            if (hatchRule_.startTokenId != 0) {
                uint256 tokenId = IL2Unicorn(l2Unicorn).mintForLevel(user_, hatchRule_.level, hatchRule_.startTokenId);
                emit HatchCallback(user_, requestId_, randomWord_, eSeries_, numberIndex_, randomNumber_, hatchRule_.level, tokenId, l2Unicorn);
            }
            unchecked{++numberIndex_;}
        }
    }

}

