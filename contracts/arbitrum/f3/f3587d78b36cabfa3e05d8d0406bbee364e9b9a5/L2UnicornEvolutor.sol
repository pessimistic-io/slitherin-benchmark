// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC721} from "./IERC721.sol";
import {IAccessControl} from "./IAccessControl.sol";

import {IL2Unicorn} from "./IL2Unicorn.sol";
import {IL2UnicornRule} from "./IL2UnicornRule.sol";

import {Pausable} from "./Pausable.sol";

import {BaseVRFConsumer} from "./BaseVRFConsumer.sol";
import {BaseMaximum} from "./BaseMaximum.sol";
import {BaseL2Unicorn} from "./BaseL2Unicorn.sol";
import {BaseL2UnicornRule} from "./BaseL2UnicornRule.sol";
import {BaseRecipient} from "./BaseRecipient.sol";

/**
 * @notice Unicorn Evolutor
 */
contract L2UnicornEvolutor is BaseVRFConsumer, BaseMaximum, BaseL2Unicorn, BaseL2UnicornRule, BaseRecipient, Pausable {

    struct EvolveResult {
        address user;
        uint256 requestId;
        uint256 randomWord;
        uint256 numberIndex;
        uint256 randomNumber;
        uint256 evolveTokenId;
        uint8 evolveLevel;
        uint8 newLevel;
    }

    event EvolveCallback (
        address indexed user,
        uint256 requestId,
        uint256 randomWord,
        uint256 numberIndex,
        uint256 randomNumber,
        uint256 evolveTokenId,
        uint8 evolveLevel,
        uint256 newTokenId,
        uint8 newLevel,
        address collection
    );

    mapping(uint256 => uint256[]) private _requestIdEvolveTokenIdArr;
    mapping(uint256 => uint8[]) private _requestIdEvolveLevelArr;

    constructor(address l2Unicorn_, address l2UnicornRule_, address recipient_, address priceFeedContractAddress_, address vrfCoordinator_, bytes32 keyHash_, uint64 vrfSubscriptionId_)
        BaseVRFConsumer(priceFeedContractAddress_, vrfCoordinator_, keyHash_, vrfSubscriptionId_)
        BaseMaximum(100)
        BaseL2Unicorn(l2Unicorn_)
        BaseL2UnicornRule(l2UnicornRule_)
        BaseRecipient(recipient_) {}

    /**
     * @notice evolve
     */
    function evolve(uint256[] calldata tokenIdArr) payable external whenNotPaused {
        //
        uint256 length_ = tokenIdArr.length;
        require(length_ <= maximum, "L2UnicornEvolutor: exceed maximum");
        require(IAccessControl(l2Unicorn).hasRole(0xaeaef46186eb59f884e36929b6d682a6ae35e1e43d8f05f058dcefb92b601461, address(this)), "L2UnicornEvolutor: l2 unicorn access denied");
        require(!Pausable(l2Unicorn).paused(), "L2UnicornEvolutor: l2 unicorn already paused");
        //
        uint256 requestId_ = beforeRequest(_msgSender());
        for (uint256 i_ = 0; i_ < length_;) {
            uint256 tokenId_ = tokenIdArr[i_];
            //取孵化的级别
            IL2UnicornRule.HatchRule memory hatchRule = IL2UnicornRule(l2UnicornRule).getHatchRuleByTokenId(tokenId_);
            //判断是否可以进化
            require(hatchRule.level >= 1 && hatchRule.level <= 6, "L2UnicornEvolutor: tokenId can't evolve");
            //回收tokenId
            IERC721(l2Unicorn).safeTransferFrom(_msgSender(), recipient, tokenId_);
            //记录进化TokenId
            _requestIdEvolveTokenIdArr[requestId_].push(tokenId_);
            //记录进化级别
            _requestIdEvolveLevelArr[requestId_].push(hatchRule.level);
            unchecked{++i_;}
        }
        require(_requestIdEvolveTokenIdArr[requestId_].length == _requestIdEvolveLevelArr[requestId_].length, "L2UnicornEvolutor: data invalid");
    }

    /**
     * @notice Callback
     */
    function fulfillRandomWords(uint256 requestId_, uint256[] memory randomWords_) override internal {
        require(randomWords_.length > 0, "L2UnicornEvolutor: random words is empty");
        uint256 randomWord_ = randomWords_[0];
        RequestInfo storage requestInfo_ = beforeFulfill(requestId_, randomWord_);
        bool immediately_ = _requestIdEvolveTokenIdArr[requestId_].length <= 10;
        if (immediately_) {
            requestInfo_.fulfilled = 1;
        }
        _fulfillByRequestId(requestId_, immediately_);
    }

    /**
     * @notice User Fulfill
     */
    function userFulfill(uint256[] memory requestIds_) external {
        require(requestIds_.length > 0, "L2UnicornEvolutor: request id is empty");
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
     * @notice 获取随机数
     */
    function getEvolveRandomNumber(uint256 randomWord_, uint256 numberIndex_) public view returns (uint256){
        bytes32 newRandomWord_ = keccak256(abi.encodePacked(randomWord_, numberIndex_));
        return uint256(newRandomWord_) % IL2UnicornRule(l2UnicornRule).modNumber();
    }

    /**
     * @notice 查看结果
     */
    function viewEvolveResults(uint256 requestId_) external view returns (EvolveResult[] memory evolveResults){
        uint256[] memory evolveTokenIdArr_ = _requestIdEvolveTokenIdArr[requestId_];
        uint8[] memory evolveLevelArr_ = _requestIdEvolveLevelArr[requestId_];
        RequestInfo memory requestInfo_ = _requestIdRequestInfo[requestId_];
        //
        uint256 length_ = evolveTokenIdArr_.length;
        evolveResults = new EvolveResult[](length_);
        for (uint256 numberIndex_ = 0; numberIndex_ < length_;) {
            (uint256 randomNumber_, IL2UnicornRule.HatchRule memory hatchRule_) = _getRandomNumberAndHatchRule(requestInfo_.randomWord, evolveLevelArr_[numberIndex_], numberIndex_);
            evolveResults[numberIndex_] = EvolveResult(
                requestInfo_.user,
                requestId_,
                requestInfo_.randomWord,
                numberIndex_,
                randomNumber_,
                evolveTokenIdArr_[numberIndex_],
                evolveLevelArr_[numberIndex_],
                hatchRule_.level
            );
            unchecked{++numberIndex_;}
        }
        return evolveResults;
    }

    function _fulfillByRequestId(uint256 requestId_, bool immediately_) private {
        RequestInfo storage requestInfo_ = _requestIdRequestInfo[requestId_];
        if (immediately_) {
            _mint(requestInfo_.user, requestId_, requestInfo_.randomWord);
            require(requestInfo_.fulfilled == 1, "L2UnicornEvolutor: request id fulfilled error");
            requestInfo_.fulfilled = 2;
        } else {
            require(requestInfo_.fulfilled == 0, "L2UnicornEvolutor: request id fulfilled error");
            requestInfo_.fulfilled = 1;
        }
        afterFulfill(requestId_);
    }

    function _getRandomNumberAndHatchRule(uint256 randomWord_, uint8 evolveLevel_, uint256 numberIndex_) private view returns (uint256 randomNumber_, IL2UnicornRule.HatchRule memory hatchRule_){
        randomNumber_ = getEvolveRandomNumber(randomWord_, numberIndex_);
        hatchRule_ = IL2UnicornRule(l2UnicornRule).getHatchRuleByEvolveTokenIdLevelRandomNum(evolveLevel_, randomNumber_);
    }

    function _mint(address user_, uint256 requestId_, uint256 randomWord_) private {
        uint256[] memory evolveTokenIdArr_ = _requestIdEvolveTokenIdArr[requestId_];
        uint8[] memory evolveLevelArr_ = _requestIdEvolveLevelArr[requestId_];
        //
        uint256 length_ = evolveTokenIdArr_.length;
        for (uint256 numberIndex_ = 0; numberIndex_ < length_;) {
            (uint256 randomNumber_, IL2UnicornRule.HatchRule memory hatchRule_) = _getRandomNumberAndHatchRule(randomWord_, evolveLevelArr_[numberIndex_], numberIndex_);
            if (hatchRule_.startTokenId != 0) {
                uint8 newLevel = hatchRule_.level;
                uint256 newTokenId = IL2Unicorn(l2Unicorn).mintForLevel(user_, newLevel, hatchRule_.startTokenId);
                emit EvolveCallback(user_, requestId_, randomWord_, numberIndex_, randomNumber_, evolveTokenIdArr_[numberIndex_], evolveLevelArr_[numberIndex_], newTokenId, newLevel, l2Unicorn);
            }
            unchecked{++numberIndex_;}
        }
    }

}

