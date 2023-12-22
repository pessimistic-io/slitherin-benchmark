// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ILevelDaoOmniStaking} from "./ILevelDaoOmniStaking.sol";
import {IMultiplierTracker} from "./IMultiplierTracker.sol";

contract LevelDaoOmniStakingHelper is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant MULTIPLIER_PRECISION = 1e6;
    uint256 public constant MAX_ALLOCATE_AMOUNT = 3.5 ether;

    IERC20 public LGO;
    ILevelDaoOmniStaking public lvlStaking;
    ILevelDaoOmniStaking public lvlUsdtStaking;
    IMultiplierTracker public multiplierTracker;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _lgo, address _lvlStaking, address _lvlUsdtStaking, address _multiplierTracker)
        external
        initializer
    {
        if (_lgo == address(0)) revert ZeroAddress();
        if (_lvlStaking == address(0)) revert ZeroAddress();
        if (_lvlUsdtStaking == address(0)) revert ZeroAddress();
        if (_multiplierTracker == address(0)) revert ZeroAddress();
        __Ownable_init();
        LGO = IERC20(_lgo);
        lvlStaking = ILevelDaoOmniStaking(_lvlStaking);
        lvlUsdtStaking = ILevelDaoOmniStaking(_lvlUsdtStaking);
        multiplierTracker = IMultiplierTracker(_multiplierTracker);
    }

    // =============== VIEW FUNCTIONS ===============
    function getLvlUsdtMultiplier() external view returns (uint256) {
        return _getLvlUsdtMultiplier();
    }

    // =============== USER FUNCTIONS ===============
    function nextEpoch() external {
        lvlStaking.nextEpoch();
        lvlUsdtStaking.nextEpoch();
    }

    function allocate(uint256 _epoch, uint256 _amount) external onlyOwner {
        if (_amount > MAX_ALLOCATE_AMOUNT) revert AmountTooHigh();
        uint256 _lvlStakingShare = _getStakingShare(address(lvlStaking), _epoch, MULTIPLIER_PRECISION);
        uint256 _lvlUsdtStakingShare = _getStakingShare(address(lvlUsdtStaking), _epoch, _getLvlUsdtMultiplier());
        uint256 _totalShare = _lvlStakingShare + _lvlUsdtStakingShare;
        if (_totalShare == 0) revert ZeroShare();
        // calculate allocate amount
        uint256 _lvlStakingAmount = _amount * _lvlStakingShare / _totalShare;
        uint256 _lvlUsdtStakingAmount = _amount - _lvlStakingAmount;
        // approve
        LGO.approve(address(lvlStaking), _lvlStakingAmount);
        LGO.approve(address(lvlUsdtStaking), _lvlUsdtStakingAmount);
        // transfer
        LGO.safeTransferFrom(msg.sender, address(this), _amount);
        lvlStaking.allocateReward(_epoch, _lvlStakingAmount);
        lvlUsdtStaking.allocateReward(_epoch, _lvlUsdtStakingAmount);

        emit Allocated(_epoch, _lvlStakingAmount, _lvlUsdtStakingAmount);
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _getStakingShare(address _staking, uint256 _epoch, uint256 _multiplier) internal view returns (uint256) {
        (,,, uint256 _stakingShare,,) = ILevelDaoOmniStaking(_staking).epochs(_epoch);
        return _stakingShare * _multiplier;
    }

    function _getLvlUsdtMultiplier() internal view returns (uint256) {
        return multiplierTracker.getStakingMultiplier();
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error ZeroShare();
    error AmountTooHigh();

    // =============== EVENTS ===============
    event Allocated(uint256 indexed _epoch, uint256 _lvlStakingAmount, uint256 _lvlUsdtStakingAmount);
}

