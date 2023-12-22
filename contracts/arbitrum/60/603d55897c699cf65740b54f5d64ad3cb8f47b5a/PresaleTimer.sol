pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./Initializable.sol";

contract PresaleTimer is Initializable, Ownable {
    using SafeMath for uint256;

    uint256 public startTime;
    uint256 public tierPeriod;
    uint256 public presalePeriod;
    uint256 public liquidityTime;
    uint256 public distributeTime;

    function initialize(
        uint256 _startTime,
        uint256 _tierPeriod,
        uint256 _presalePeriod,
        uint256 _liquidityTime,
        uint256 _distributeTime,
        address _owner
    ) external initializer {
        Ownable.initialize(msg.sender);
        startTime = _startTime;
        tierPeriod = _tierPeriod;
        presalePeriod = _presalePeriod;
        liquidityTime = _liquidityTime;
        distributeTime = _distributeTime;
        //Due to issue in oz testing suite, the msg.sender might not be owner
        _transferOwnership(_owner);
    }

    function setStartTime(
        uint256 _startTime,
        uint256 _tierPeriod,
        uint256 _presalePeriod,
        uint256 _liquidityTime,
        uint256 _distributeTime
    ) external onlyOwner {
        startTime = _startTime;
        tierPeriod = _tierPeriod;
        presalePeriod = _presalePeriod;
        liquidityTime = _liquidityTime;
        distributeTime = _distributeTime;
    }

    function isTierPresalePeriod() external view returns (bool) {
        return (startTime != 0 &&
            now > startTime &&
            now < startTime.add(tierPeriod));
    }

    function isPresalePeriod() external view returns (bool) {
        return (startTime != 0 &&
            now > startTime &&
            now < startTime.add(presalePeriod));
    }

    function isPresaleFinished() external view returns (bool) {
        return (startTime != 0 && now > startTime.add(presalePeriod));
    }

    function isLiquidityEnabled() external view returns (bool) {
        return (startTime != 0 && now > startTime.add(liquidityTime));
    }

    function isTierDistributionTime() external view returns (bool) {
        return (startTime != 0 && now > startTime.add(distributeTime));
    }

    function isTierClaimable(uint256 _timestamp) external view returns (bool) {
        return (startTime != 0 && _timestamp < startTime.add(distributeTime));
    }
}

