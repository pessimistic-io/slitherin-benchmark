// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC721} from "./IERC721.sol";
import {IAccessControl} from "./IAccessControl.sol";

import {IL2Unicorn} from "./IL2Unicorn.sol";
import {IL2UnicornRule} from "./IL2UnicornRule.sol";

import {IL2MetaCube} from "./IL2MetaCube.sol";
import {IL2MetaCubeRule} from "./IL2MetaCubeRule.sol";

import {Pausable} from "./Pausable.sol";

import {BaseVRFConsumer} from "./BaseVRFConsumer.sol";
import {BaseMaximum} from "./BaseMaximum.sol";
import {BaseL2} from "./BaseL2.sol";
import {BaseL2Unicorn} from "./BaseL2Unicorn.sol";
import {BaseL2UnicornRule} from "./BaseL2UnicornRule.sol";
import {BaseL2MetaCube} from "./BaseL2MetaCube.sol";
import {BaseL2MetaCubeRule} from "./BaseL2MetaCubeRule.sol";
import {BaseRecipient} from "./BaseRecipient.sol";

/**
 * @notice 魔方合成
 */
contract L2MetaCubeMerger is BaseVRFConsumer, BaseMaximum, BaseL2Unicorn, BaseL2UnicornRule, BaseL2MetaCube, BaseL2MetaCubeRule, BaseRecipient, Pausable {

    struct UnicornTokenIdArray {
        uint256[] data;
    }

    struct MergeResult {
        address user;
        uint256 requestId;
        uint256 randomWord;
        uint8 numberIndex;
        uint256 randomNumber;
        uint8 unicornLevel;
        uint8 metaCubeLevel;
    }

    event MergeCallback (
        address indexed user,
        uint256 requestId,
        uint256 randomWord,
        uint8 numberIndex,
        uint256 randomNumber,
        uint8 unicornLevel,
        uint8 metaCubeLevel,
        uint256 metaCubeTokenId,
        address metaCubeCollection
    );

    mapping(uint256 => uint8[]) private _requestIdUnicornLevelArr;

    constructor(address l2Unicorn_, address l2UnicornRule_, address l2MetaCube_, address l2MetaCubeRule_, address recipient_, address priceFeedContractAddress_, address vrfCoordinator_, bytes32 keyHash_, uint64 vrfSubscriptionId_)
        BaseVRFConsumer(priceFeedContractAddress_, vrfCoordinator_, keyHash_, vrfSubscriptionId_)
        BaseMaximum(100)
        BaseL2Unicorn(l2Unicorn_)
        BaseL2UnicornRule(l2UnicornRule_)
        BaseL2MetaCube(l2MetaCube_)
        BaseL2MetaCubeRule(l2MetaCubeRule_)
        BaseRecipient(recipient_) {}

    /**
     * @notice 合成
     */
    function merge(UnicornTokenIdArray[] calldata unicornTokenIdArray_) payable external whenNotPaused {
        uint256 length_ = unicornTokenIdArray_.length;
        require(length_ > 0 && length_ <= maximum, "L2MetaCubeMerger: exceed maximum");
        require(IAccessControl(l2MetaCube).hasRole(0xaeaef46186eb59f884e36929b6d682a6ae35e1e43d8f05f058dcefb92b601461, address(this)), "L2MetaCubeMerger: l2 meta cube access denied");
        require(!Pausable(l2Unicorn).paused(), "L2MetaCubeMerger: l2 unicorn already paused");
        require(!Pausable(l2MetaCube).paused(), "L2MetaCubeMerger: l2 meta cube already paused");
        //
        uint256 requestId_ = beforeRequest(_msgSender());
        for (uint8 i_ = 0; i_ < length_;) {
            //
            uint256[] memory unicornTokenIdArr = unicornTokenIdArray_[i_].data;
            //验证是否是3个
            require(unicornTokenIdArr.length == 3, "L2MetaCubeMerger: merge unicorn token id insufficient 3");
            //
            uint256 unicornTokenId0_ = unicornTokenIdArr[0];
            IL2UnicornRule.HatchRule memory hatchRule0 = IL2UnicornRule(l2UnicornRule).getHatchRuleByTokenId(unicornTokenId0_);
            //
            uint256 unicornTokenId1_ = unicornTokenIdArr[1];
            IL2UnicornRule.HatchRule memory hatchRule1 = IL2UnicornRule(l2UnicornRule).getHatchRuleByTokenId(unicornTokenId1_);
            //
            uint256 unicornTokenId2_ = unicornTokenIdArr[2];
            IL2UnicornRule.HatchRule memory hatchRule2 = IL2UnicornRule(l2UnicornRule).getHatchRuleByTokenId(unicornTokenId2_);
            //验证3个是否相同级别
            require(hatchRule0.level >= 1 && hatchRule0.level <= 6 && hatchRule0.level == hatchRule1.level && hatchRule0.level == hatchRule2.level, "L2MetaCubeMerger: merge unicorn token id level invalid");
            //回收
            IERC721(l2Unicorn).safeTransferFrom(_msgSender(), recipient, unicornTokenId0_);
            IERC721(l2Unicorn).safeTransferFrom(_msgSender(), recipient, unicornTokenId1_);
            IERC721(l2Unicorn).safeTransferFrom(_msgSender(), recipient, unicornTokenId2_);
            //记录合成级别
            _requestIdUnicornLevelArr[requestId_].push(hatchRule0.level);
            //
            unchecked{++i_;}
        }
    }

    /**
     * @notice 合成回调
     */
    function fulfillRandomWords(uint256 requestId_, uint256[] memory randomWords_) override internal {
        require(randomWords_.length > 0, "L2MetaCubeMerger: random words is empty");
        uint256 randomWord_ = randomWords_[0];
        RequestInfo storage requestInfo_ = beforeFulfill(requestId_, randomWord_);
        bool immediately_ = _requestIdUnicornLevelArr[requestId_].length <= 10;
        if (immediately_) {
            requestInfo_.fulfilled = 1;
        }
        _fulfillByRequestId(requestId_, immediately_);
    }

    /**
     * @notice 履行
     */
    function userFulfill(uint256[] memory requestIds_) external {
        require(requestIds_.length > 0, "L2MetaCubeMerger: request id is empty");
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

    /**
     * @notice 获取合成随机数
     */
    function getMergeRandomNumber(uint256 randomWord_, uint256 numberIndex_) public view returns (uint256){
        bytes32 newRandomWord_ = keccak256(abi.encodePacked(randomWord_, numberIndex_));
        return uint256(newRandomWord_) % IL2MetaCubeRule(l2MetaCubeRule).modNumber();
    }

    /**
     * @notice 查看合成结果
     */
    function viewMergeResults(uint256 requestId_) external view returns (MergeResult[] memory mergeResults){
        uint8[] memory unicornLevelArr_ = _requestIdUnicornLevelArr[requestId_];
        RequestInfo memory requestInfo_ = _requestIdRequestInfo[requestId_];
        //
        uint256 length_ = unicornLevelArr_.length;
        mergeResults = new MergeResult[](length_);
        for (uint8 numberIndex_ = 0; numberIndex_ < length_;) {
            (uint256 randomNumber_, IL2MetaCubeRule.TokenIdRule memory tokenIdRule_) = _getRandomNumberAndTokenIdRule(requestInfo_.randomWord, unicornLevelArr_[numberIndex_], numberIndex_);
            mergeResults[numberIndex_] = MergeResult(
                requestInfo_.user,
                requestId_,
                requestInfo_.randomWord,
                numberIndex_,
                randomNumber_,
                unicornLevelArr_[numberIndex_],
                tokenIdRule_.level
            );
            unchecked{++numberIndex_;}
        }
        return mergeResults;
    }

    function _getRandomNumberAndTokenIdRule(uint256 randomWord_, uint8 unicornLevel_, uint256 numberIndex_) private view returns (uint256 randomNumber_, IL2MetaCubeRule.TokenIdRule memory tokenIdRule_){
        randomNumber_ = getMergeRandomNumber(randomWord_, numberIndex_);
        tokenIdRule_ = IL2MetaCubeRule(l2MetaCubeRule).getTokenIdRuleByUnicornLevelRandomNum(unicornLevel_, randomNumber_);
    }

    function _fulfillByRequestId(uint256 requestId_, bool immediately_) private {
        RequestInfo storage requestInfo_ = _requestIdRequestInfo[requestId_];
        if (immediately_) {
            _mint(requestInfo_.user, requestId_, requestInfo_.randomWord);
            require(requestInfo_.fulfilled == 1, "L2MetaCubeMerger: request id fulfilled error");
            requestInfo_.fulfilled = 2;
        } else {
            require(requestInfo_.fulfilled == 0, "L2MetaCubeMerger: request id fulfilled error");
            requestInfo_.fulfilled = 1;
        }
        afterFulfill(requestId_);
    }

    function _mint(address user_, uint256 requestId_, uint256 randomWord_) private {
        uint8[] memory unicornLevelArr_ = _requestIdUnicornLevelArr[requestId_];
        uint256 length_ = unicornLevelArr_.length;
        for (uint8 numberIndex_ = 0; numberIndex_ < length_;) {
            (uint256 randomNumber_, IL2MetaCubeRule.TokenIdRule memory tokenIdRule_) = _getRandomNumberAndTokenIdRule(randomWord_, unicornLevelArr_[numberIndex_], numberIndex_);
            if (tokenIdRule_.startTokenId != 0) {
                uint8 newLevel = tokenIdRule_.level;
                uint256 newTokenId = IL2MetaCube(l2MetaCube).mintForLevel(user_, newLevel, tokenIdRule_.startTokenId);
                emit MergeCallback(user_, requestId_, randomWord_, numberIndex_, randomNumber_, unicornLevelArr_[numberIndex_], newLevel, newTokenId, l2MetaCube);
            }
            unchecked{++numberIndex_;}
        }
    }

}

