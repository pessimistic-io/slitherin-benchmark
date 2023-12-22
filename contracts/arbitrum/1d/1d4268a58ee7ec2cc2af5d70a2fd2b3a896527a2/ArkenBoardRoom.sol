// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Math} from "./Math.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract ArkenBoardRoom is
    ReentrancyGuard,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    struct MemberSeat {
        uint256 currentSnapshotIndex;
        uint256 balance;
        uint256 share;
        uint256 firstEpoch;
        uint256 totalEpoch;
        uint256 unlockTime;
    }

    /*///////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    // tokens
    address public ve;
    address public reward;
    uint8 internal constant VE_DECIMALS = 18;
    uint8 internal constant RPS_PRECISION = 36;
    uint8 internal rpsOffset;

    // wallet
    address public reserveFund;
    address private _authorizer;

    // epoch
    // uint256 public constant EPOCH_DURATION = 1 weeks;
    // uint256 public constant MAXTIME = 104 weeks;
    uint256 public constant EPOCH_DURATION = 5 minutes;
    uint256 public constant MAXTIME = 104 * EPOCH_DURATION;
    uint256 internal currentEpoch;

    uint256 public maxCapacity;
    uint256 public totalBalance;
    uint256 public totalRewardPaid;
    uint256 public totalRewardAdded;

    uint256 public lastEpochTime;

    address public penaltyFeeWallet;
    uint256 public earlyWithdrawFeeRate;

    // boardroom
    BoardroomSnapshot[] public boardroomHistory;
    uint256[1000000000] public totalShares; // uint256[epoch]
    mapping(address => MemberSeat) public members;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposited(
        address indexed provider,
        uint256 value,
        uint256 indexed lockDuration,
        uint256 ts
    );
    event Withdrawn(address indexed provider, uint256 value, uint256 ts);
    event EmergencyWithdrawn(
        address indexed provider,
        uint256 value,
        uint256 ts
    );
    event RewardPaid(address indexed member, uint256 earned);
    event RewardAdded(address indexed provider, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address _ve,
        address _reward,
        address _reserveFund,
        uint256 _firstEpochTime
    ) external initializer {
        PausableUpgradeable.__Pausable_init();
        OwnableUpgradeable.__Ownable_init();

        ve = _ve;
        reward = _reward;
        reserveFund = _reserveFund;

        rpsOffset = RPS_PRECISION - IERC20Extented(reward).decimals();

        maxCapacity = 100_000_000_000000000000000000; // 100_000_000 veARKEN
        totalBalance = 0;

        currentEpoch = 1;

        lastEpochTime = _firstEpochTime - getEpochDuration();

        penaltyFeeWallet = _reserveFund;
        earlyWithdrawFeeRate = 5_000;
    }

    modifier onlyAuthorizer() {
        require(owner() == _msgSender(), 'Authorization: caller is authorized');
        _;
    }

    function authorizer() public view returns (address) {
        return _authorizer;
    }

    function setAuthorizer(address newAuthorizer) external onlyOwner {
        _authorizer = newAuthorizer;
    }

    function setMaxCapacity(uint256 _amount) external onlyOwner {
        require(
            _amount > totalBalance,
            'Can only set max capacity higher than current balance'
        );
        maxCapacity = _amount;
    }

    function setPenaltyFeeWallet(address _penaltyFeeWallet) external onlyOwner {
        require(
            _penaltyFeeWallet != address(0),
            'Set penalty fee wallet to the zero address'
        );
        penaltyFeeWallet = _penaltyFeeWallet;
    }

    function setEarlyWithdrawFeeRate(
        uint256 _earlyWithdrawFeeRate
    ) external onlyOwner {
        require(_earlyWithdrawFeeRate <= 10_000, 'Maximum fee rate is 10_000'); // <= 100%
        earlyWithdrawFeeRate = _earlyWithdrawFeeRate;
    }

    function setNextEpochTime(uint256 _nextEpochTime) external onlyOwner {
        require(
            _nextEpochTime >= block.timestamp,
            'nextEpochTime could not be the past'
        );
        lastEpochTime = _nextEpochTime - getEpochDuration();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                GETTER
    //////////////////////////////////////////////////////////////*/

    function getCurrentEpoch() external view returns (uint256) {
        return currentEpoch;
    }

    function getEpochDuration() public view virtual returns (uint256) {
        return EPOCH_DURATION;
    }

    function isMemberExists(address _member) external view returns (bool) {
        return members[_member].balance != 0;
    }

    function _getMemberShareAtEpoch(
        address _member,
        uint256 _epoch
    ) internal view returns (uint256) {
        if (_epoch == 0) {
            return 0;
        }
        MemberSeat memory seat = members[_member];
        uint256 firstEpoch = seat.firstEpoch;
        // avoid overflow
        if (firstEpoch + seat.totalEpoch == 0) {
            return 0;
        }
        if (
            firstEpoch <= _epoch && _epoch <= firstEpoch + seat.totalEpoch - 1
        ) {
            return members[_member].share;
        }
        return 0;
    }

    function getMemberShareCurEpoch(
        address _member
    ) external view returns (uint256) {
        return _getMemberShareAtEpoch(_member, currentEpoch);
    }

    function getMemberShareAtEpoch(
        address _member,
        uint256 _epoch
    ) external view returns (uint256) {
        return _getMemberShareAtEpoch(_member, _epoch);
    }

    function getTotalShareCurEpoch() external view returns (uint256) {
        return totalShares[currentEpoch - 1];
    }

    function getRemainingEpoch(
        address _member
    ) external view returns (uint256) {
        MemberSeat memory seat = members[_member];

        if (seat.balance > 0) {
            return (seat.totalEpoch + seat.firstEpoch) - currentEpoch;
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

    function lastSnapshotIndexOf(
        address _member
    ) internal view returns (uint256) {
        uint256 lastEpoch = members[_member].firstEpoch +
            members[_member].totalEpoch;
        if (lastEpoch == 0) {
            return 0;
        }
        return Math.min(boardroomHistory.length, lastEpoch - 1);
    }

    function earned(address _member) public view returns (uint256) {
        MemberSeat memory seat = members[_member];

        uint256 rewardEarned = 0;
        for (
            uint256 i = seat.currentSnapshotIndex;
            i < lastSnapshotIndexOf(_member);
            i++
        ) {
            uint256 epochReward = (boardroomHistory[i].rewardPerShare *
                seat.share) / (10 ** (rpsOffset + VE_DECIMALS));
            rewardEarned = rewardEarned + epochReward;
        }

        return rewardEarned;
    }

    function claimReward() external {
        _claimReward(msg.sender);
    }

    function _claimReward(address _to) internal {
        uint256 _earned = earned(_to);
        members[_to].currentSnapshotIndex = boardroomHistory.length; // move index to future

        if (_earned > 0) {
            // safe reward transfer
            IERC20 _reward = IERC20(reward);
            uint256 _rewardBal = _reward.balanceOf(address(this));

            require(_earned <= _rewardBal, 'Insufficient reward balance');

            _reward.safeTransfer(_to, _earned);
            totalRewardPaid += _earned;
            emit RewardPaid(msg.sender, _earned);
        }
    }

    modifier checkEpoch() {
        uint256 _nextEpochTime = lastEpochTime + getEpochDuration();
        require(
            block.timestamp >= _nextEpochTime,
            'Can only allocate after epoch time end'
        );

        _;

        lastEpochTime = _nextEpochTime;
        currentEpoch += 1;
    }

    function allocateRewardManually(
        uint256 _amount
    ) public nonReentrant checkEpoch whenNotPaused onlyAuthorizer {
        require(_amount > 0, 'Cannot allocate 0 reward');
        require(
            totalShares[currentEpoch - 1] > 0,
            'Cannot allocate when share is 0'
        );

        uint256 rps = (_amount * (10 ** (rpsOffset + VE_DECIMALS))) /
            totalShares[currentEpoch - 1];

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: _amount,
            rewardPerShare: rps
        });
        boardroomHistory.push(newSnapshot);

        IERC20(reward).safeTransferFrom(reserveFund, address(this), _amount);
        totalRewardAdded += _amount;
        emit RewardAdded(msg.sender, _amount);
    }

    function calculateShare(
        uint256 _value,
        uint256 _lockDuration
    ) public pure returns (uint256) {
        return (_value * _lockDuration) / MAXTIME;
    }

    function stake(
        uint256 _value,
        uint256 _lockDuration
    ) external nonReentrant whenNotPaused {
        _stake(_value, _lockDuration, msg.sender);
    }

    /// @notice Stake `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    function _stake(
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) internal {
        require(members[_to].balance == 0, 'Already staked');

        uint256 lockDuration = (_lockDuration / getEpochDuration()) *
            getEpochDuration();
        uint256 unlockTime = block.timestamp + lockDuration;

        require(_value > 0); // dev: need non-zero value
        require(
            unlockTime > block.timestamp,
            'Can only lock until time in the future'
        );
        require(
            unlockTime <= block.timestamp + MAXTIME,
            'Lock can be 2 years max'
        );
        require(
            totalBalance + _value <= maxCapacity,
            'Staking amount exceed max capacity'
        );

        uint256 share = calculateShare(_value, _lockDuration);

        members[_to].currentSnapshotIndex = currentEpoch - 1;
        members[_to].balance = _value;
        members[_to].share = share;
        members[_to].firstEpoch = currentEpoch;
        members[_to].totalEpoch = _lockDuration / getEpochDuration();
        members[_to].unlockTime = unlockTime;

        for (
            uint256 i = currentEpoch - 1;
            i < currentEpoch - 1 + members[_to].totalEpoch;
            i++
        ) {
            totalShares[i] = totalShares[i] + share;
        }

        IERC20(ve).safeTransferFrom(_to, address(this), _value);
        totalBalance += _value;

        emit Deposited(_to, _value, lockDuration, block.timestamp);
    }

    function increaseStake(
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        _increaseStake(msg.sender, _amount);
    }

    function resetEpochTimer() external nonReentrant whenNotPaused {
        _increaseStake(msg.sender, 0);
    }

    function _increaseStake(address _to, uint256 _amount) internal {
        require(members[_to].balance > 0, 'The member does not exist');
        require(block.timestamp < members[_to].unlockTime, 'Lock is expired');
        require(
            totalBalance + _amount <= maxCapacity,
            'Staking amount exceed max capacity'
        );

        _claimReward(_to);

        MemberSeat memory seat = members[_to];

        uint256 lockDuration = getEpochDuration() * seat.totalEpoch;

        MemberSeat memory newSeat = MemberSeat({
            currentSnapshotIndex: currentEpoch - 1,
            balance: seat.balance,
            share: seat.share,
            firstEpoch: currentEpoch,
            totalEpoch: seat.totalEpoch,
            unlockTime: block.timestamp + lockDuration
        });

        if (_amount > 0) {
            newSeat.balance = seat.balance + _amount;
            newSeat.share = calculateShare(newSeat.balance, lockDuration);
            uint256 diffShare = newSeat.share - seat.share;

            for (
                uint256 i = currentEpoch - 1;
                i < seat.firstEpoch + seat.totalEpoch - 1;
                i++
            ) {
                totalShares[i] = totalShares[i] + diffShare;
            }

            IERC20(ve).safeTransferFrom(_to, address(this), _amount);
            totalBalance += _amount;
        }

        for (
            uint256 i = seat.firstEpoch + seat.totalEpoch - 1;
            i < newSeat.firstEpoch + newSeat.totalEpoch - 1;
            i++
        ) {
            totalShares[i] = totalShares[i] + newSeat.share;
        }

        members[_to] = newSeat;

        emit Deposited(_to, newSeat.balance, lockDuration, block.timestamp);
    }

    function withdraw() external nonReentrant whenNotPaused {
        _withdraw(msg.sender);
    }

    function withdrawFor(
        address _member
    ) external nonReentrant whenNotPaused onlyOwner {
        _withdraw(_member);
    }

    function canWithdraw(address _member) external view returns (bool) {
        return block.timestamp > members[_member].unlockTime;
    }

    function _withdraw(address _to) internal {
        require(members[_to].balance > 0, 'The member does not exist');
        require(
            block.timestamp > members[_to].unlockTime,
            'Lock is not expired'
        );

        _claimReward(_to);

        uint256 balance = members[_to].balance;

        members[_to] = MemberSeat({
            currentSnapshotIndex: 0,
            balance: 0,
            share: 0,
            firstEpoch: 0,
            totalEpoch: 0,
            unlockTime: 0
        });

        IERC20(ve).safeTransfer(_to, balance);
        totalBalance -= balance;

        emit Withdrawn(_to, balance, block.timestamp);
    }

    function emergencyWithdraw() external nonReentrant whenNotPaused {
        require(members[msg.sender].balance > 0, 'The member does not exist');

        MemberSeat memory seat = members[msg.sender];

        _claimReward(msg.sender);

        for (
            uint256 i = currentEpoch - 1;
            i < seat.firstEpoch + seat.totalEpoch - 1;
            i++
        ) {
            totalShares[i] = totalShares[i] - seat.share;
        }

        members[msg.sender] = MemberSeat({
            currentSnapshotIndex: 0,
            balance: 0,
            share: 0,
            firstEpoch: 0,
            totalEpoch: 0,
            unlockTime: 0
        });

        uint256 _fee = (seat.balance * earlyWithdrawFeeRate) / 10_000;
        IERC20(ve).safeTransfer(penaltyFeeWallet, _fee);
        IERC20(ve).safeTransfer(msg.sender, seat.balance - _fee);
        totalBalance -= seat.balance;

        emit EmergencyWithdrawn(msg.sender, seat.balance, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                               EMERGENCY
    //////////////////////////////////////////////////////////////*/

    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.safeTransfer(owner(), _token.balanceOf(address(this)));
    }
}

