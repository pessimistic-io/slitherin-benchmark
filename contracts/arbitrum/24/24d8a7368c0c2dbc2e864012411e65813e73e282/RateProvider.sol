// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./Ownable2Step.sol";
import "./SafeERC20.sol";
import "./IERC6372.sol";
import { IErrors } from "./Interfaces.sol";
import { IRewardTracker } from "./Interfaces.sol";

interface IRateProvider is IERC6372 {
  struct RateCheckpoint {
    uint48 fromTsIncl;
    uint32 rate; // in bps 1e4. e.g. 1_500_000 = 150
  }

  function getRate() external view returns (uint256);

  function getPastRate(uint256 timepoint) external view returns (uint256);

  event RateChanged(uint32 _oldRate, uint32 _newRate);
}

contract RateProvider is IRateProvider, IErrors, Ownable2Step {
  uint private constant BASIS_POINTS_DIVISOR = 1e4;
  mapping(address => bool) public isHandler;
  RateCheckpoint[] private _rates; // in bps 1e4
  uint112 public upperBound;
  uint112 public lowerBound;

  constructor() {
    // initial rate
    _updateRate(1_730_000);
    upperBound = 3_000_000;
    lowerBound = 1_000_000;

    isHandler[msg.sender] = true;
  }

  function clock() public view returns (uint48) {
    return uint48(block.timestamp);
  }

  function CLOCK_MODE() public view returns (string memory) {
    require(clock() == block.timestamp, 'RateProvider: broken clock mode');
    return 'mode=timestamp';
  }

  function getRate() external view returns (uint256) {
    unchecked {
      return _rates[_rates.length - 1].rate;
    }
  }

  function getPastRate(uint256 timepoint) external view returns (uint256) {
    require(timepoint < clock(), 'RateProvider: future lookup');

    for (uint i = _rates.length; i > 0; ) {
      unchecked {
        RateCheckpoint memory _cp = _rates[i - 1];

        if (_cp.fromTsIncl > timepoint) {
          --i;
          continue;
        } else {
          return _cp.rate;
        }
      }
    }

    return BASIS_POINTS_DIVISOR;
  }

  function _updateRate(uint32 _newRate) private {
    _rates.push(RateCheckpoint({ fromTsIncl: clock(), rate: _newRate }));
  }

  function _validateHandler() private view {
    if (!isHandler[msg.sender]) revert UNAUTHORIZED('RateProvider: !handler');
  }

  function setRate(uint32 _newRate, address _bonusTracker) external {
    _validateHandler();

    emit RateChanged(_rates[_rates.length - 1].rate, _newRate);

    if (_bonusTracker != address(0)) {
      IRewardTracker(_bonusTracker).updateRewards();
    }

    if (_newRate < lowerBound) revert FAILED('RateProvider: invalid rate lb');
    if (_newRate > upperBound) revert FAILED('RateProvider: invalid rate ub');

    _updateRate(_newRate);
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function setBounds(uint112 _upper, uint112 _lower) external onlyOwner {
    if (_lower >= _upper) revert FAILED('RateProvider: lower > upper');

    upperBound = _upper;
    lowerBound = _lower;
  }
}

