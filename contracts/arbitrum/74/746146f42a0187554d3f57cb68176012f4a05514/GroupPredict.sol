// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.4;
import "./Initializable.sol";
import "./EDataTypes.sol";
import "./IEvent.sol";

import "./console.sol";

contract GroupPredict is Initializable {
    function hostFee(address _eventDataAddress, uint256 _eventId) external view returns (uint256) {
        EDataTypes.Event memory _event = IEvent(_eventDataAddress).info(_eventId);
        return _event.hostFee;
    }

    function platformFee() external view returns (uint256) {
        return 100;
    }

    function platFormfeeBefore() external view returns (uint256) {
        return 0;
    }

    function getAmountHasFee(uint256 _amount, uint256 _reward) external view returns (uint256) {
        return _reward - _amount;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
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
        return 0;
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
        return true;
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
            if (_predictOptionStats[_event.resultIndex] == 0) {
                return _predictions.predictionAmount;
            }
            require(_event.resultIndex == _predictions.predictOptions, "no-reward");
        }

        _reward = ((_predictStats + _liquidityPool) * _predictions.predictionAmount) / _predictOptionStats[_index];
    }

    /**
     * @dev Calculates reward
     */
    function calculateRewardSponsor(
        address _eventDataAddress,
        uint256 _eventId,
        uint256 _predictStats,
        uint256[] calldata _predictOptionStats,
        EDataTypes.Prediction calldata _predictions,
        uint256 _oneHundredPrecent,
        uint256 _liquidityPool
    ) public view returns (uint256 _reward) {
        EDataTypes.Event memory _event = IEvent(_eventDataAddress).info(_eventId);
        uint256 _index = _predictions.predictOptions;
        uint256 _odd = _event.odds[_index];

        if (_event.status == EDataTypes.EventStatus.FINISH && _predictOptionStats[_event.resultIndex] == 0) {
            return 0;
        }

        _reward = (_liquidityPool * _predictions.predictionAmount) / _predictOptionStats[_index];
    }

    /**
     * @dev Calculates sponsor
     */
    function calculateSponsor(
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
        _reward = (_liquidityPool * _predictionAmount) / (_predictOptionStats[_index] + _predictionAmount);
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
        _reward =
            ((_predictStats + _liquidityPool + _predictionAmount) * _predictionAmount) /
            (_predictOptionStats[_index] + _predictionAmount);
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
        if (_predictOptionStats[_event.resultIndex] == 0) {
            _remainLP = _liquidityPool;
        } else {
            _remainLP = 0;
        }
    }
}

