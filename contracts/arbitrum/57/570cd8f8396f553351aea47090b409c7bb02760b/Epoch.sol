pragma solidity >0.6.0;

import "./SafeMath.sol";

import "./Operator.sol";

contract Epoch is Operator {
    using SafeMath for uint;

    uint private period;
    uint private startTime;
    uint private lastEpochTime;
    uint private epoch;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        uint _period,
        uint _startTime,
        uint _startEpoch
    ) public {
        period = _period;
        startTime = _startTime;
        epoch = _startEpoch;
        lastEpochTime = startTime.sub(period);
    }

    /* ========== Modifier ========== */

    modifier checkStartTime {
        require(block.timestamp >= startTime, 'Epoch: not started yet');

        _;
    }

    modifier checkEpoch {
        uint _nextEpochPoint = nextEpochPoint();
        if (block.timestamp < _nextEpochPoint) {
            require(msg.sender == operator(), 'Epoch: only operator allowed for pre-epoch');
            _;
        } else {
            _;

            uint unixDiff = block.timestamp.sub(_nextEpochPoint);
            uint epochsLapsed = unixDiff.div(period);

            lastEpochTime = _nextEpochPoint.add(epochsLapsed.mul(period));

            epoch = epoch.add(epochsLapsed.add(1));
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getCurrentEpoch() public view returns (uint) {
        return epoch;
    }

    function getPeriod() public view returns (uint) {
        return period;
    }

    function getStartTime() public view returns (uint) {
        return startTime;
    }

    function getLastEpochTime() public view returns (uint) {
        return lastEpochTime;
    }

    function nextEpochPoint() public view returns (uint) {
        return lastEpochTime.add(period);
    }

    /* ========== GOVERNANCE ========== */

    function setPeriod(uint _period) external onlyOperator {
        require(_period >= 15 && _period <= 48 hours, '_period: out of range');
        period = _period;
    }

    function setEpoch(uint _epoch) external onlyOperator {
        epoch = _epoch;
    }
}

