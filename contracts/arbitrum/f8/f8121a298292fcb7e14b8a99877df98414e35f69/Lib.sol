//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IPits } from "./IPits.sol";
import { DevelopmentGroundIsLocked } from "./Error.sol";

library Lib {
    function getDevGroundBonesReward(
        uint256 _currentLockPeriod,
        uint256 _lockPeriod,
        uint256 _lastRewardTime,
        IPits _pits
    ) internal view returns (uint256) {
        if (_lockPeriod == 0) return 0;
        uint256 rewardRate = getRewardRate(_lockPeriod);

        uint256 time = (block.timestamp - _lastRewardTime) / 1 days;

        if (time == 0) return 0;
        uint256 toBeRomoved = calculateFinalReward(_currentLockPeriod, _pits);
        return ((rewardRate * time) - (toBeRomoved * rewardRate)) * 10 ** 18;
    }

    function calculatePrimarySkill(
        uint256 _bonesStaked,
        uint256 _amountPosition,
        uint256 _currentLockPeriod,
        uint256 _tokenId,
        IPits _pits,
        mapping(uint256 => mapping(uint256 => uint256)) storage trackTime,
        mapping(uint256 => mapping(uint256 => uint256)) storage trackToken
    ) internal view returns (uint256) {
        if (_bonesStaked == 0) return 0;
        uint256 amount;
        uint256 i = 1;
        for (; i <= _amountPosition; ) {
            uint256 time = (block.timestamp - trackTime[_tokenId][i]) / 1 days;
            uint256 stakedAmount = trackToken[_tokenId][trackTime[_tokenId][i]];
            amount += (time * stakedAmount);
            unchecked {
                ++i;
            }
        }
        uint256 toBeRemoved = calculateFinalReward(_currentLockPeriod, _pits);
        return (amount - (toBeRemoved * 10 ** 21)) / 10 ** 4;
    }

    function calculateFinalReward(
        uint256 /* _currentLockPeriod*/,
        IPits /*_pits*/
    ) internal view returns (uint256) {
        return 0;
        // if (_currentLockPeriod == 0) {
        //     console.log(_currentLockPeriod);
        //     if (_pits.getTotalDaysOff() == 0) {
        //         return
        //             _pits.getTimeOut() == 0
        //                 ? 0
        //                 : (block.timestamp - _pits.getTimeOut()) / 1 days;
        //     } else {
        //         return _pits.getTotalDaysOff();
        //     }
        // } else {
        //     uint256 howLong = (block.timestamp - _pits.getTimeOut()) / 1 days;

        //     if (_pits.getTotalDaysOff() == 0) {
        //         return 0;
        //     } else {
        //         return
        //             _pits.getTimeOut() == _currentLockPeriod &&
        //                 _pits.validation()
        //                 ? 0
        //                 : (_pits.getTotalDaysOff() -
        //                     (_pits.getDaysOff(_currentLockPeriod) + howLong));
        //     }
        // }
    }

    function getRewardRate(
        uint _lockTime
    ) internal pure returns (uint256 rewardRate) {
        if (_lockTime == 50 days) rewardRate = 10;
        if (_lockTime == 100 days) rewardRate = 50;
        if (_lockTime == 150 days) rewardRate = 100;
    }

    function pitsValidation(IPits _pits) internal view {
        if (!_pits.validation()) revert DevelopmentGroundIsLocked();
    }

    function removeItem(
        uint256[] storage _element,
        uint256 _removeElement
    ) internal {
        uint256 i;
        for (; i < _element.length; ) {
            if (_element[i] == _removeElement) {
                _element[i] = _element[_element.length - 1];
                _element.pop();
                break;
            }

            unchecked {
                ++i;
            }
        }
    }
}

