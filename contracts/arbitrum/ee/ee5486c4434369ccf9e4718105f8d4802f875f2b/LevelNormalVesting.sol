// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import {ILevelOmniStaking} from "./ILevelOmniStaking.sol";

/**
 * @title LevelNormalVesting
 * @author Level
 * @notice Convert preLVL tokens to LVL tokens.
 * The preLVL tokens will be converted into LVL every second and will fully vest over 365 days.
 * The preLVL tokens that have been converted into LVL tokens will be burned whenever user claim their vested LVL.
 * Require reserve LVL tokens in LVL Omni-Chain Staking to vesting preLVL.
 */
contract LevelNormalVesting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

    struct UserInfo {
        /// @notice Amount of preLVL tokens user want to convert to LVL.
        uint256 vestingAmount;
        /// @notice Accumulate vested preLVL tokens.
        uint256 accVestedAmount;
        /// @notice Amount of LVL tokens the user claimed.
        uint256 claimedAmount;
        /// @notice Start time of the current vesting process.
        uint256 startVestingTime;
    }

    uint256 public constant RESERVE_RATE_PRECISION = 1e6;
    uint256 public constant MAX_RESERVE_RATE = 10e6;
    uint256 public constant MIN_RESERVE_RATE = 1e6;
    uint256 public constant VESTING_DURATION = 365 days;

    IERC20 public LVL;
    IBurnableERC20 public preLVL;
    ILevelOmniStaking public lvlOmniStaking;

    /// @notice If the user wants vesting `x` preLVL tokens, the user needs stake `x * reserveRate` LVL tokens in LVL Omni-Chain Staking.
    uint256 public reserveRate;

    mapping(address userAddress => UserInfo) public users;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _lvl, address _preLvl, address _lvlOmniStaking, uint256 _reserveRate)
        external
        initializer
    {
        if (_lvl == address(0)) revert ZeroAddress();
        if (_preLvl == address(0)) revert ZeroAddress();
        if (_lvlOmniStaking == address(0)) revert ZeroAddress();
        __Ownable_init();
        __ReentrancyGuard_init();
        LVL = IERC20(_lvl);
        preLVL = IBurnableERC20(_preLvl);
        lvlOmniStaking = ILevelOmniStaking(_lvlOmniStaking);
        _setReserveRate(_reserveRate);
    }

    // =============== VIEW FUNCTIONS ===============
    /**
     * @notice Amount of LVL tokens reserves in LVL Omni-Chain Staking to vest preLVL.
     */
    function getReservedAmount(address _user) external view returns (uint256) {
        UserInfo memory _userInfo = users[_user];
        if (_userInfo.vestingAmount == 0) {
            return 0;
        }
        uint256 _notVestedAmount = _userInfo.vestingAmount - _getVestedAmount(_user);
        return _notVestedAmount * reserveRate / RESERVE_RATE_PRECISION;
    }

    /**
     * @notice get vested amount of LVL
     */
    function claimable(address _user) public view returns (uint256 _claimableAmount) {
        UserInfo memory _userInfo = users[_user];
        uint256 _totalVestedAmount = _userInfo.accVestedAmount + _getVestedAmount(_user);
        if (_totalVestedAmount > _userInfo.claimedAmount) {
            _claimableAmount = _totalVestedAmount - _userInfo.claimedAmount;
        }
    }

    // =============== USER FUNCTIONS ===============
    /**
     * @notice Users can convert preLVL tokens to LVL tokens.
     *   The vesting process will be restart if the user add more preLVL tokens to vest. Note that the vested LVL is unchange, user can claim these tokens anytime
     */
    function startVesting(address _to, uint256 _amount) external nonReentrant {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        UserInfo memory _userInfo = users[_to];
        uint256 _stakedAmount = lvlOmniStaking.stakedAmounts(_to);
        uint256 _vestedAmount = _getVestedAmount(_to);
        uint256 _newVestingAmount = _userInfo.vestingAmount + _amount - _vestedAmount;

        if (_newVestingAmount * reserveRate > _stakedAmount * RESERVE_RATE_PRECISION) {
            revert ExceededVestableAmount();
        }

        _userInfo.vestingAmount = _newVestingAmount;
        _userInfo.accVestedAmount += _vestedAmount;
        _userInfo.startVestingTime = block.timestamp;
        users[_to] = _userInfo;
        preLVL.safeTransferFrom(msg.sender, address(this), _amount);
        emit VestingStarted(msg.sender, _to, _userInfo.vestingAmount, _amount);
    }

    /**
     * @notice Users can stop vesting and claim amount of LVL tokens converted.
     * @param _to the address receive the remaining preLVL
     */
    function stopVesting(address _to) external nonReentrant {
        if (_to == address(0)) revert ZeroAddress();
        address _sender = msg.sender;
        UserInfo memory _userInfo = users[_sender];
        uint256 _vestingAmount = _userInfo.vestingAmount;
        if (_vestingAmount == 0) revert ZeroVestingAmount();

        uint256 _claimableAmount = claimable(_sender);
        uint256 _notVestedAmount = _vestingAmount - _getVestedAmount(_sender);
        delete users[_sender];

        if (_notVestedAmount != 0) {
            preLVL.safeTransfer(_to, _notVestedAmount);
        }

        if (_claimableAmount != 0) {
            LVL.safeTransfer(_to, _claimableAmount);
            preLVL.burn(_claimableAmount);
            emit Claimed(_sender, _to, _claimableAmount);
        }

        emit VestingStopped(_sender, _to, _vestingAmount, _notVestedAmount);
    }

    /**
     * @notice User claim the vested LVL amount
     * @param _to the address receive LVL
     */
    function claim(address _to) external nonReentrant {
        if (_to == address(0)) revert ZeroAddress();
        address _sender = msg.sender;
        UserInfo storage _userInfo = users[_sender];
        uint256 _claimableAmount = claimable(_sender);
        if (_claimableAmount == 0) revert ZeroReward();
        _userInfo.claimedAmount += _claimableAmount;

        LVL.safeTransfer(_to, _claimableAmount);
        preLVL.burn(_claimableAmount);

        emit Claimed(_sender, _to, _claimableAmount);
    }

    // =============== RESTRICTED ===============
    function setReserveRate(uint256 _reserveRate) external onlyOwner {
        _setReserveRate(_reserveRate);
    }

    function recoverFund(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        LVL.safeTransfer(_to, _amount);
        emit FundRecovered(_to, _amount);
    }

    // =============== INTERNAL FUNCTIONS ===============
    /**
     * @notice Calculate the converted LVL amount of users since start vesting time.
     */
    function _getVestedAmount(address _user) internal view returns (uint256) {
        UserInfo memory _userInfo = users[_user];
        if (_userInfo.vestingAmount == 0) {
            return 0;
        }
        uint256 _elapsedTime = block.timestamp - _userInfo.startVestingTime;
        if (_elapsedTime >= VESTING_DURATION) {
            return _userInfo.vestingAmount;
        }
        return _userInfo.vestingAmount * _elapsedTime / VESTING_DURATION;
    }

    function _setReserveRate(uint256 _reserveRate) internal {
        if (_reserveRate > MAX_RESERVE_RATE) revert ReserveRateTooHigh();
        if (_reserveRate < MIN_RESERVE_RATE) revert ReserveRateTooLow();
        reserveRate = _reserveRate;
        emit ReserveRateSet(_reserveRate);
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error ZeroAmount();
    error ZeroReward();
    error ZeroVestingAmount();
    error ReserveRateTooHigh();
    error ReserveRateTooLow();
    error ExceededVestableAmount();

    // =============== EVENTS ===============
    event ReserveRateSet(uint256 _reserveRate);
    event FundRecovered(address indexed _to, uint256 _amount);
    event VestingStarted(address indexed _from, address indexed _to, uint256 _newVestingAmount, uint256 _addedAmount);
    event VestingStopped(address indexed _from, address indexed _to, uint256 _vestingAmount, uint256 _notVestedAmount);
    event Claimed(address indexed _from, address indexed _to, uint256 _amount);
}

