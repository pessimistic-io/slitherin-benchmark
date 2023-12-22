// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.4;
import "./Initializable.sol";
import "./EDataTypes.sol";
import "./IEvent.sol";

// import "hardhat/console.sol";

contract MultipleChoices is Initializable {
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
        uint256 winAmount = (_predictOptionStats[_index] + _predictValue) * _odd;

        return totalAmount >= winAmount;
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
            require(_event.resultIndex == _predictions.predictOptions, "no-reward");
        }

        _reward = (_predictions.predictionAmount * _odd) / _oneHundredPrecent;
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

            if (_event.resultIndex == idx) {
                _remainLP -= (_predictOptionStats[idx] * _odds[idx]) / _oneHundredPrecent;
            }
        }
    }
}

