// SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./BaseJumper.sol";

/// @title BaseJumper vesting contract
abstract contract BaseJumperVesting is Ownable, ReentrancyGuard {

    using SafeERC20 for BaseJumper;

    BaseJumper public immutable baseJumper;
    address public immutable treasury;
    uint public constant PERCENT_DENOMINATOR = 100;
    uint public vestingStartDate;
    uint public gonTotal;
    uint public gonWithdrawn;
    uint public percentOfSupply;
    uint public vestingPeriod;

    event VestingStarted();
    event Claimed(address user, uint amount);

    modifier onlyBeforeStart() {
        require(!_hasVestingStarted(), "BaseJumperVesting: Vesting has already started");
        _;
    }

    modifier onlyAfterStart() {
        require(_hasVestingStarted(), "BaseJumperVesting: Vesting has not started yet");
        _;
    }

    modifier onlyVestor(address _address) {
        require(_hasVestment(_address), "BaseJumperVesting: Not eligible to claim");
        _;
    }

    /// @param _baseJumper BaseJumper address
    /// @param _treasury Treasury address
    constructor(address payable _baseJumper, address _treasury, uint _percentOfSupply, uint _vestingPeriod) Ownable() {
        require(_baseJumper != address(0), "BaseJumperVesting: _baseJumper cannot be the zero address");
        require(_treasury != address(0), "BaseJumperVesting: _treasury cannot be the zero address");
        baseJumper = BaseJumper(_baseJumper);
        treasury = _treasury;
        percentOfSupply = _percentOfSupply;
        vestingPeriod = _vestingPeriod;
    }

    /// @notice Amount to transfer
    /// @return total - Total amount
    function amountToTransfer() public view onlyBeforeStart returns (uint total) {
        total = baseJumper.totalSupply() * percentOfSupply / PERCENT_DENOMINATOR;
    }

    /// @notice Start the vesting period (owner)
    function startVesting() external onlyOwner onlyBeforeStart {
        _startVesting();
        vestingStartDate = block.timestamp;
        emit VestingStarted();
    }

    /// @notice Claim presale tokens (vestors)
    function claim() external nonReentrant onlyAfterStart onlyVestor(_msgSender()) {
        uint gonValue = _claim();
        baseJumper.gonTransfer(_msgSender(), gonValue);
        emit Claimed(_msgSender(), gonValue);
    }

    /// @notice Available claim amount
    /// @param _address Wallet address
    /// @return amount Amount available
    function availableToClaim(address _address) external view onlyAfterStart onlyVestor(_address) returns (uint amount) {
        uint gonValue = _availableToClaim(_address);
        amount = baseJumper.calculateAmount(gonValue);
    }

    /// @notice Total vested amount (affected by rebasing)
    /// @return uint Total vested amount
    function totalAmountVested() external view returns (uint) {
        return baseJumper.calculateAmount(gonTotal);
    }

    /// @notice Total withdrawn amount (affected by rebasing)
    /// @return uint Total withdrawn amount
    function totalAmountWithdrawn() external view returns (uint) {
        return baseJumper.calculateAmount(gonWithdrawn);
    }

    /// @dev Calculate the amount to claim for a given vestment
    /// @param _total Total gon value
    /// @param _withdrawn Withdrawn gon value
    /// @return uint Claimable amount
    function _calculateClaimableAmount(uint _total, uint _withdrawn) internal view returns (uint) {
        uint endDate = vestingStartDate + vestingPeriod;
        if (block.timestamp >= endDate) {
            return _total - _withdrawn;
        } else {
            uint timePassed = block.timestamp - vestingStartDate;
            uint totalAmount = baseJumper.calculateAmount(_total);
            uint unlocked = totalAmount * timePassed / vestingPeriod;
            uint gonUnlocked = baseJumper.calculateGonValue(unlocked);
            if (gonUnlocked > _withdrawn) {
                return gonUnlocked - _withdrawn;
            }
        }
        return 0;
    }

    /// @dev Has vesting started
    /// @return bool True - Vesting has started, False - Vesting has not started
    function _hasVestingStarted() internal view returns (bool) {
        return vestingStartDate > 0;
    }

    function _startVesting() internal virtual;

    function _claim() internal virtual returns (uint gonValue);

    function _availableToClaim(address _address) internal virtual view returns (uint gonValue);

    function _hasVestment(address _address) internal virtual view returns (bool);
}

