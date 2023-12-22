// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.4;
import "./Initializable.sol";
import "./EDataTypes.sol";
import "./IEvent.sol";

import "./console.sol";

contract Handicap is Initializable {
    function hostFee(address _eventDataAddress, uint256 _eventId) external view returns (uint256) {
        return 0;
    }

    function platformFee() external view returns (uint256) {
        return 0;
    }

    function platFormfeeBefore() external view returns (uint256) {
        return 50;
    }

    function getAmountHasFee(uint256 _amount, uint256 _reward) external view returns (uint256) {
        return _amount;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function indexOf(string[] memory a, string memory b) internal pure returns (uint256) {
        for (uint256 i = 0; i < a.length; i++) {
            if (compareStrings(a[i], b)) {
                return i;
            }
        }
        require(false, "cannot-find-index");
    }

    function maxPayout(
        address _eventDataAddress,
        uint256 _eventId,
        uint256 _predictStats,
        uint256[] calldata _predictOptionStats,
        uint256 _odd,
        uint256 _liquidityPool,
        uint256 _oneHundredPrecent,
        uint256 _index
    ) external view returns (uint256) {
        uint256 totalAmount = _predictStats + _liquidityPool;
        uint256 winAmount = (_predictOptionStats[_index] * _odd) / _oneHundredPrecent;

        uint256 winPercent = _odd - _oneHundredPrecent;

        return ((totalAmount - winAmount) * _oneHundredPrecent) / winPercent;
    }

    function validatePrediction(
        uint256 _predictStats,
        uint256[] calldata _predictOptionStats,
        uint256 _predictValue,
        uint256 _odd,
        uint256 _liquidityPool,
        uint256 _oneHundredPrecent,
        uint256 _index
    ) external view returns (bool) {
        uint256 totalAmount = (_predictStats + _predictValue + _liquidityPool) * _oneHundredPrecent;
        uint256 totalAmountA = _predictOptionStats[_index] + _predictValue;
        uint256 winAmountA = totalAmountA * _odd;

        bool validate1 = totalAmount >= winAmountA;
        bool validate4 = (_index == 0 || _index == 4);

        return validate1 && validate4;
    }

    /**
     * @dev Calculates reward
     */
    function calculateReward(
        address _eventDataAddress,
        uint256 _eventId,
        uint256 _predictStats,
        uint256[] calldata _predictOptionStats,
        EDataTypes.Prediction calldata _predictions,
        uint256 _oneHundredPrecent,
        uint256 _liquidityPool,
        bool _validate
    ) public view returns (uint256 _reward) {
        EDataTypes.Event memory _event = IEvent(_eventDataAddress).info(_eventId);
        uint256 _index = _predictions.predictOptions;
        uint256 _odd = _event.odds[_index];

        if (_validate) {
            require((_index == 0 && _event.resultIndex != 4) || (_index == 4 && _event.resultIndex != 0), "no-reward");
        } else {
            return (_predictions.predictionAmount * _odd) / _oneHundredPrecent;
        }

        if ((_index == 0 && _event.resultIndex == 0) || (_index == 4 && _event.resultIndex == 4)) {
            _reward = (_predictions.predictionAmount * _odd) / _oneHundredPrecent;
        }
        if ((_index == 0 && _event.resultIndex == 1) || (_index == 4 && _event.resultIndex == 3)) {
            _reward = (_predictions.predictionAmount * (_oneHundredPrecent + _odd)) / 2 / _oneHundredPrecent;
        }
        if ((_index == 0 && _event.resultIndex == 2) || (_index == 4 && _event.resultIndex == 2)) {
            _reward = _predictions.predictionAmount;
        }
        if ((_index == 0 && _event.resultIndex == 3) || (_index == 4 && _event.resultIndex == 1)) {
            _reward = _predictions.predictionAmount / 2;
        }
    }

    /**
     * @dev Calculates reward
     */
    function calculatePotentialReward(
        address _eventDataAddress,
        uint256 _eventId,
        uint256 _predictStats,
        uint256[] calldata _predictOptionStats,
        uint256 _predictionAmount,
        uint256 _odd,
        uint256 _oneHundredPrecent,
        uint256 _index,
        uint256 _liquidityPool
    ) public view returns (uint256 _reward) {
        EDataTypes.Event memory _event = IEvent(_eventDataAddress).info(_eventId);

        _reward = (_predictionAmount * _odd) / _oneHundredPrecent;
    }

    /**
     * @dev Calculates reward
     */
    function calculateRemainLP(
        address _eventDataAddress,
        uint256 _eventId,
        uint256 _predictStats,
        uint256[] calldata _predictOptionStats,
        uint256[] calldata _odds,
        uint256 _oneHundredPrecent,
        uint256 _liquidityPool
    ) public view returns (uint256 _remainLP) {
        EDataTypes.Event memory _event = IEvent(_eventDataAddress).info(_eventId);
        _remainLP = _liquidityPool;

        for (uint256 idx = 0; idx < _predictOptionStats.length; ++idx) {
            _remainLP += _predictOptionStats[idx];

            if ((idx == 0 && _event.resultIndex != 4) || (idx == 4 && _event.resultIndex != 0)) {
                if ((idx == 0 && _event.resultIndex == 0) || (idx == 4 && _event.resultIndex == 4)) {
                    _remainLP -= (_predictOptionStats[idx] * _odds[idx]) / _oneHundredPrecent;
                }
                if ((idx == 0 && _event.resultIndex == 1) || (idx == 4 && _event.resultIndex == 3)) {
                    _remainLP -=
                        (_predictOptionStats[idx] * (_oneHundredPrecent + _odds[idx])) /
                        2 /
                        _oneHundredPrecent;
                }
                if ((idx == 0 && _event.resultIndex == 2) || (idx == 4 && _event.resultIndex == 2)) {
                    _remainLP -= _predictOptionStats[idx];
                }
                if ((idx == 0 && _event.resultIndex == 3) || (idx == 4 && _event.resultIndex == 1)) {
                    _remainLP -= _predictOptionStats[idx] / 2;
                }
            }
        }
    }
}

