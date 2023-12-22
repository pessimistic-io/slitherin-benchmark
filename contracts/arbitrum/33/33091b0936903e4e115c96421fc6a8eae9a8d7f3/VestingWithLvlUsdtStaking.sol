// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import {ILevelNormalVesting} from "./ILevelNormalVesting.sol";
import {ILevelOmniStaking} from "./ILevelOmniStaking.sol";
import {IMultiplierTracker} from "./IMultiplierTracker.sol";

/**
 * @title VestingWithLvlUsdtStaking
 * @author Level
 * @notice Convert preLVL tokens to LVL tokens.
 * The preLVL tokens will be converted into LVL every second and will fully vest over 365 days.
 * The preLVL tokens that have been converted into LVL tokens will be burned whenever user claim their vested LVL.
 * Require reserve LVL-USDT tokens in Omni-Chain Staking to vest preLVL.
 */
contract VestingWithLvlUsdtStaking is
    ILevelNormalVesting,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

    uint256 public constant RESERVE_RATE_PRECISION = 1e6;
    uint256 public constant MAX_RESERVE_RATE = 10e6;
    uint256 public constant MIN_RESERVE_RATE = 1e6;
    uint256 public constant VESTING_DURATION = 365 days;

    IERC20 public LVL;
    IBurnableERC20 public preLVL;
    ILevelOmniStaking public omniChainStaking;

    /// @notice reserveRate of LVL tokens used to vest preLVL token.
    uint256 public baseReserveRate;

    mapping(address userAddress => UserInfo) public users;
    IMultiplierTracker public multiplierTracker;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lvl,
        address _preLvl,
        address _omniChainStaking,
        address _multiplierTracker,
        uint256 _baseReserveRate
    ) external initializer {
        if (_lvl == address(0)) revert ZeroAddress();
        if (_preLvl == address(0)) revert ZeroAddress();
        if (_omniChainStaking == address(0)) revert ZeroAddress();
        if (_multiplierTracker == address(0)) revert ZeroAddress();
        __Ownable_init();
        __ReentrancyGuard_init();
        LVL = IERC20(_lvl);
        preLVL = IBurnableERC20(_preLvl);
        omniChainStaking = ILevelOmniStaking(_omniChainStaking);
        multiplierTracker = IMultiplierTracker(_multiplierTracker);
        _setBaseReserveRate(_baseReserveRate);
    }

    // =============== VIEW FUNCTIONS ===============
    /**
     * @notice Calculate `reserveRate` of LVL-USDT tokens used to vest preLVL tokens.
     */
    function reserveRate() external view returns (uint256) {
        return baseReserveRate * RESERVE_RATE_PRECISION / multiplierTracker.getVestingMultiplier();
    }

    function reserveRate(uint256 precision) external view returns (uint256) {
        return baseReserveRate * precision / multiplierTracker.getVestingMultiplier();
    }

    /**
     * @notice Calculate amount of LVL user must staked to a staking contract to vest preLVL.
     */
    function getReservedAmount(address _user) external view returns (uint256) {
        UserInfo memory _userInfo = users[_user];
        uint256 lpMultiplier = multiplierTracker.getVestingMultiplier();
        return _userInfo.totalVestingAmount * baseReserveRate / lpMultiplier;
    }

    /**
     * @notice Get vested amount of preLVL tokens till now.
     */
    function getVestedAmount(address _user) external view returns (uint256) {
        return _getVestedAmount(_user);
    }

    /**
     * @notice Get vesting status of user.
     */
    function isFullyVested(address _user) external view returns (bool) {
        UserInfo memory _userInfo = users[_user];
        return _getVestedAmount(_user) >= _userInfo.totalVestingAmount;
    }

    /**
     * @notice Get amount of LVL tokens user can claim.
     */
    function claimable(address _user) public view returns (uint256 _claimableAmount) {
        UserInfo memory _userInfo = users[_user];
        uint256 _vestedAmount = _getVestedAmount(_user);
        if (_vestedAmount > _userInfo.claimedAmount) {
            _claimableAmount = _vestedAmount - _userInfo.claimedAmount;
        }
    }

    // =============== USER FUNCTIONS ===============
    /**
     * @notice Users can convert preLVL tokens to LVL tokens.
     *   The vesting process will be restart if the user add more preLVL tokens to vest. Note that the vested LVL is unchange, user can claim these tokens anytime
     */
    function startVesting(uint256 _amount) external virtual nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        address _sender = msg.sender;
        UserInfo storage _userInfo = users[_sender];
        uint256 _totalVestingAmount = _userInfo.totalVestingAmount + _amount;
        uint256 lpMultiplier = multiplierTracker.getVestingMultiplier();
        if (_totalVestingAmount * baseReserveRate > _getStakedAmount(_sender) * lpMultiplier) {
            revert ExceededVestableAmount();
        }
        _updateVesting(_sender);
        _userInfo.totalVestingAmount = _totalVestingAmount;
        preLVL.safeTransferFrom(_sender, address(this), _amount);
        emit VestingStarted(_sender, _amount);
    }

    /**
     * @notice Users can stop vesting and claim amount of LVL tokens converted.
     * @param _to the address receive the remaining preLVL
     */
    function stopVesting(address _to) external nonReentrant {
        if (_to == address(0)) revert ZeroAddress();
        address _sender = msg.sender;
        _updateVesting(_sender);
        UserInfo memory _userInfo = users[_sender];
        uint256 totalVestingAmount = _userInfo.totalVestingAmount;
        if (totalVestingAmount == 0) revert ZeroVestingAmount();
        _claimFresh(_sender, _to);
        uint256 _notVestedAmount = totalVestingAmount - _userInfo.accVestedAmount;
        delete users[_sender];

        if (_notVestedAmount != 0) {
            preLVL.safeTransfer(_to, _notVestedAmount);
        }
        emit VestingStopped(_sender, _to, totalVestingAmount, _notVestedAmount);
    }

    /**
     * @notice User claim the vested LVL amount
     * @param _to the address receive LVL
     */
    function claim(address _to) external nonReentrant {
        if (_to == address(0)) revert ZeroAddress();
        address _sender = msg.sender;
        _updateVesting(_sender);
        _claimFresh(_sender, _to);
    }

    // =============== RESTRICTED ===============
    function setOmniChainStaking(address _omniChainStaking) external onlyOwner {
        if (_omniChainStaking == address(0)) revert ZeroAddress();
        omniChainStaking = ILevelOmniStaking(_omniChainStaking);
        emit OmniChainStakingSet(_omniChainStaking);
    }

    function setBaseReserveRate(uint256 _baseReserveRate) external onlyOwner {
        _setBaseReserveRate(_baseReserveRate);
    }

    function recoverFund(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        LVL.safeTransfer(_to, _amount);
        emit FundRecovered(_to, _amount);
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _updateVesting(address _user) internal {
        UserInfo memory _userInfo = users[_user];
        uint256 _pendingVestedAmount = _getPendingVestedAmount(_user);
        _userInfo.accVestedAmount += _pendingVestedAmount;
        _userInfo.lastUpdateTime = block.timestamp;
        users[_user] = _userInfo;
    }

    function _claimFresh(address _user, address _to) internal {
        UserInfo storage _userInfo = users[_user];
        uint256 _claimableAmount = _userInfo.accVestedAmount - _userInfo.claimedAmount;
        if (_claimableAmount > 0) {
            _userInfo.claimedAmount += _claimableAmount;
            LVL.safeTransfer(_to, _claimableAmount);
            preLVL.burn(_claimableAmount);

            emit Claimed(_user, _to, _claimableAmount);
        }
    }

    function _setBaseReserveRate(uint256 _baseReserveRate) internal {
        if (_baseReserveRate > MAX_RESERVE_RATE) revert ReserveRateTooHigh();
        if (_baseReserveRate < MIN_RESERVE_RATE) revert ReserveRateTooLow();
        baseReserveRate = _baseReserveRate;
        emit BaseReserveRateSet(_baseReserveRate);
    }

    /**
     * @notice Return LVL amount user stake in staking contract.
     */
    function _getStakedAmount(address _user) internal view returns (uint256) {
        return omniChainStaking.stakedAmounts(_user);
    }

    /**
     * @notice Calculate the converted LVL amount of users since last vesting time.
     */
    function _getPendingVestedAmount(address _user) internal view returns (uint256 _pendingVestedAmount) {
        UserInfo memory _userInfo = users[_user];
        uint256 _totalVestingAmount = _userInfo.totalVestingAmount;
        if (_totalVestingAmount == 0) {
            return 0;
        }
        uint256 _elapsedTime = block.timestamp - _userInfo.lastUpdateTime;
        _pendingVestedAmount = (_totalVestingAmount * _elapsedTime) / VESTING_DURATION;
        uint256 _unvestedAmount = _totalVestingAmount - _userInfo.accVestedAmount;
        if (_pendingVestedAmount > _unvestedAmount) {
            return _unvestedAmount;
        }
    }

    /**
     * @notice Return the vested amount of preLVL tokens till now.
     */
    function _getVestedAmount(address _user) internal view returns (uint256) {
        UserInfo memory _userInfo = users[_user];
        return _userInfo.accVestedAmount + _getPendingVestedAmount(_user);
    }

    event BaseReserveRateSet(uint256 _baseReserveRate);
}

