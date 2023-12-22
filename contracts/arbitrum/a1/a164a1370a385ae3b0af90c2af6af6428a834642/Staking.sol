// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./ERC20_IERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { Interpolating } from "./Interpolating.sol";
import { IStaking, UserStake } from "./IStaking.sol";
import { ISnapshottable } from "./ISnapshottable.sol";
//import { SafeERC20 } from '../libraries/SafeERC20.sol';
import { SafeERC20 } from "./SafeERC20.sol";



contract Staking is Ownable, Interpolating, IStaking {
    // TODO add Withdrawable parent class
    using SafeMath for uint256;

    // the amount of the tokens used for calculation may need to mature over time
    Interpolation public tokenVesting;
    // over time some of the tokens may be available for early withdrawal
    Interpolation public withdrawalVesting;
    // there may be a penalty for withdrawing everything early
    Interpolation public emergencyWithdrawPenalty;

    mapping(address => UserStake) public stakes;
    address[] public stakers;
    mapping(address => bool) public isPenaltyCollector;
    mapping(address => bool) public isSnapshotter;
    IERC20 public token;
    uint256 public penalty = 0;
    uint256 public minimumStakeToBeListed; // how much token is required to be listed in the stakers variable

    uint256[] public snapshotBlockNumbers;
    // blockNumber => address => amount
    mapping(uint256 => mapping(address => uint256)) public snapshots;
    // blockNumber => bool
    mapping(uint256 => bool) public snapshotExists;

    event Staked(address indexed account, uint256 amount, uint256 stakingTime);
    event Withdrawn(address indexed account, uint256 amount);
    event EmergencyWithdrawn(address indexed account, uint256 amount, uint256 penalty);

    constructor(IERC20 _token, uint256 vestingLength, uint256 _minimumStakeToBeListed) {
        require(address(_token) != address(0), "Token address cannot be 0x0");

        token = _token;
        minimumStakeToBeListed = _minimumStakeToBeListed;

        // by default emergency withdrawal penalty matures from 80% to 0%
        setEmergencyWithdrawPenalty(Interpolation(0, vestingLength, INTERPOLATION_DIVISOR.mul(8).div(10), 0));
        // by default withdrawals mature from 0% to 100%
        setWithdrawalVesting(Interpolation(0, vestingLength, 0, INTERPOLATION_DIVISOR));
        // by default calculation token amount is fully mature immediately
        setTokenVesting(Interpolation(0, 0, INTERPOLATION_DIVISOR, INTERPOLATION_DIVISOR));

        // eliminate the possibility of a real snapshot at idx 0
        snapshotBlockNumbers.push(0);
    }


    ///////////////////////////////////////
    // Core functionality
    ///////////////////////////////////////

    function getStake(address _account) public view override returns (UserStake memory) {
        return stakes[_account];
    }
    function stake(uint256 _amount) public {
        return _stake(msg.sender, msg.sender, _amount);
    }
    function stakeFor(address _account, uint256 _amount) public {
        return _stake(msg.sender, _account, _amount);
    }
    function _stake(address from, address account, uint256 amount) internal {
        require(amount > 0, "Amount must be greater than 0");

        _updateSnapshots(0, type(uint256).max, account);

        uint256 allowance = token.allowance(from, address(this));
        require(allowance >= amount, "Check the token allowance");

        UserStake memory userStake = stakes[account];
        uint256 preStakeAmount = userStake.amount;
        if (userStake.amount == 0) {
            // default case
            userStake.amount = amount;
            userStake.depositBlock = block.number;
            userStake.withdrawBlock = block.number;
            userStake.emergencyWithdrawalBlock = block.number;
        } else {
            // An attacker could potentially stake token into a target account and 
            //  to mess with their emergency withdrawal ratios. If we normalize the
            //  deposit time and the emergency withdrawal settings are reasonable,
            //  the victim is not negatively affected and the attacker just loses 
            //  funds.

            // lerp the blocks based on existing amount vs added amount
            userStake.depositBlock =             lerp(userStake.amount, userStake.amount.add(amount), userStake.depositBlock,             block.number, userStake.amount);
            userStake.withdrawBlock =            lerp(userStake.amount, userStake.amount.add(amount), userStake.withdrawBlock,            block.number, userStake.amount);
            userStake.emergencyWithdrawalBlock = lerp(userStake.amount, userStake.amount.add(amount), userStake.emergencyWithdrawalBlock, block.number, userStake.amount);
            userStake.amount = userStake.amount.add(amount);
        }
        stakes[account] = userStake;

        emit Staked(account, amount, block.timestamp);

        SafeERC20.safeTransferFrom(token, from, address(this), amount);

        // to prevent dust attacks, only add user as staker if they cross the stake threshold
        if (preStakeAmount < minimumStakeToBeListed && userStake.amount >= minimumStakeToBeListed) {
            // make sure the user can't easily spam himself into the stakers list
            if (stakers.length < 3 || (stakers[stakers.length - 1] != account && stakers[stakers.length - 2] != account && stakers[stakers.length - 3] != account)) {
                stakers.push(account);
            }
        }
    }

    function updateSnapshots(uint256 startIdx, uint256 endIdx) external {
        _updateSnapshots(startIdx, endIdx, msg.sender);
    }
    function _updateSnapshots(uint256 startIdx, uint256 endIdx, address account) internal {
        if (snapshotBlockNumbers.length == 0) {
            return; // early abort
        }

        require(endIdx > startIdx, "endIdx must be greater than startIdx");
        uint256 lastSnapshotBlockNumber = stakes[account].lastSnapshotBlockNumber;
        uint256 lastBlockNumber = snapshotBlockNumbers[snapshotBlockNumbers.length - 1];

        if (stakes[account].amount == 0) {
            stakes[account].lastSnapshotBlockNumber = lastBlockNumber;
            return; // early abort
        }

        // iterate backwards through snapshots
        if (snapshotBlockNumbers.length < endIdx) {
            endIdx = uint256(snapshotBlockNumbers.length).sub(1);
        }
        for (uint256 i = endIdx;  i > startIdx;  --i) {
            uint256 blockNumber = snapshotBlockNumbers[i];

            if (lastSnapshotBlockNumber == blockNumber) {
                break; // done with user
            }

            // address => amount
            mapping(address => uint256) storage _snapshot = snapshots[blockNumber];

            // update the vested amount
            _snapshot[account] = _calculateVestedTokensAt(account, blockNumber);
        }

        // set user as updated
        stakes[account].lastSnapshotBlockNumber = lastBlockNumber;
    }
    function snapshot() external onlySnapshotter {
        if (!snapshotExists[block.number]) {
            snapshotBlockNumbers.push(block.number);
            snapshotExists[block.number] = true;
            // TODO trigger events here, + withdraw + deposit + emergencyWithdraw
        }
    }

    function withdraw(uint256 _amount) external {
        _updateSnapshots(0, type(uint256).max, msg.sender);

        return _withdraw(msg.sender, _amount);
    }
    function _withdraw(address account, uint256 _amount) internal {
        require(_amount > 0, "Amount must be greater than 0");

        // cap to deal with frontend rounding errors
        UserStake memory userStake = stakes[account];
        if (userStake.amount < _amount) {
            _amount = userStake.amount;
        }

        uint256 withdrawableAmount = getWithdrawable(account);
        require(withdrawableAmount >= _amount, "Insufficient withdrawable balance");

        userStake.amount = userStake.amount.sub(_amount);
        userStake.withdrawBlock = lerp(0, withdrawableAmount, userStake.withdrawBlock, block.number, _amount);
        stakes[account] = userStake;

        emit Withdrawn(account, _amount);

        SafeERC20.safeTransfer(token, account, _amount);
    }

    function emergencyWithdraw(uint256 _amount) external {
        return _emergencyWithdraw(msg.sender, _amount);
    }
    function _emergencyWithdraw(address account, uint256 _amount) internal {
        require(_amount > 0, "Amount must be greater than 0");

        // cap to deal with frontend rounding errors
        UserStake memory userStake = stakes[account];
        if (userStake.amount < _amount) {
            _amount = userStake.amount;
        }

        // max out the normal withdrawable first out of respect for the user
        uint256 withdrawableAmount = getWithdrawable(account);
        if (withdrawableAmount > 0) {
            if (withdrawableAmount >= _amount) {
                return _withdraw(account, _amount);
            } else {
                _withdraw(account, withdrawableAmount);
                _amount = _amount.sub(withdrawableAmount);
            }
            // update data after the withdraw
            userStake = stakes[account];
        }

        // figure out the numbers for the emergency withdraw
        require(userStake.amount <= _amount, "Insufficient emergency-withdrawable balance");
        userStake.amount = userStake.amount.sub(_amount);
        uint256 returnedAmount = getEmergencyWithdrawPenaltyAmountReturned(account, _amount);
        uint256 _penalty = _amount.sub(returnedAmount);
        userStake.withdrawBlock = lerp(0, userStake.amount, userStake.emergencyWithdrawalBlock, block.number, _amount);

        // account for the penalty
        penalty = penalty.add(_penalty);
        stakes[account] = userStake;

        emit EmergencyWithdrawn(account, _amount, _penalty);

        SafeERC20.safeTransfer(token, account, _amount);
    }


    ///////////////////////////////////////
    // Housekeeping
    ///////////////////////////////////////

    function changeOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be 0x0");

        transferOwnership(_newOwner);
    }
    function setTokenVesting(Interpolation memory _value) public onlyOwner {
        tokenVesting = _value;
    }
    function setWithdrawalVesting(Interpolation memory _value) public onlyOwner {
        withdrawalVesting = _value;
    }
    function setEmergencyWithdrawPenalty(Interpolation memory _value) public onlyOwner {
        emergencyWithdrawPenalty = _value;
    }
    function sendPenalty(address to) external returns (uint256) {
        require(msg.sender == owner() || isPenaltyCollector[msg.sender], "Only owner or penalty collector can send penalty");

        uint256 _amount = penalty;
        penalty = 0;

        SafeERC20.safeTransfer(token, to, _amount);

        return _amount;
    }
    function setPenaltyCollector(address _collector, bool _status) external onlyOwner {
        isPenaltyCollector[_collector] = _status;
    }
    function setSnapshotter(address _snapshotter, bool _state) external onlyOwner {
        isSnapshotter[_snapshotter] = _state;
    }
    modifier onlySnapshotter() {
        require(isSnapshotter[msg.sender], "Only snapshotter can call this function");
        _;
    }
    function setMinimumStakeToBeListed(uint256 _minimumStakeToBeListed) external onlyOwner {
        minimumStakeToBeListed = _minimumStakeToBeListed;
    }
    function getStakersCount() external view returns (uint256) {
        return stakers.length;
    }
    function getStakers(uint256 idx) external view returns (address) {
        return stakers[idx];
    }
    function setStakers(address[] calldata _stakers) external onlyOwner {
        // reset-stakers function, for dust attack recovery
        stakers = _stakers;
    }


    ///////////////////////////////////////
    // View functions
    ///////////////////////////////////////

    function _calculateVestedTokensAt(address user, uint256 blockNumber) internal view returns (uint256) {
        if (blockNumber < stakes[user].depositBlock) {
            // ideally this should never happen but as a safety precaution..
            return 0;
        }

        return lerpValue(tokenVesting, blockNumber.sub(stakes[user].depositBlock), stakes[user].amount);
    }
    function getVestedTokens(address user) external view returns (uint256) {
        return _calculateVestedTokensAt(user, block.number);
    }
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external view returns (uint256) {
        // try to look up snapshot directly and use that
        require(snapshotExists[blockNumber], "No snapshot exists for this block");
        // is the user snapshotted for this?
        if (stakes[user].lastSnapshotBlockNumber >= blockNumber) {
            // use the snapshot
            mapping(address => uint256) storage _snapshot = snapshots[blockNumber];
            return _snapshot[user];
        }

        // no snapshot so we calculate the snapshot as it would have been at that time in the past
        return _calculateVestedTokensAt(user, blockNumber);
    }
    function getWithdrawable(address user) public view returns (uint256) {
        return lerpValue(withdrawalVesting, block.number.sub(stakes[user].withdrawBlock), stakes[user].amount);
    }
    function getEmergencyWithdrawPenalty(address user) external view returns (uint256) {
        // account for allowed withdrawal
        uint256 _amount = stakes[user].amount;
        uint256 withdrawable = getWithdrawable(user);
        if (_amount <= withdrawable) {
            return 0;
        }
        _amount = _amount.sub(withdrawable);
        return lerpValue(emergencyWithdrawPenalty, block.number.sub(stakes[user].withdrawBlock), _amount);
    }
    function getVestedTokensPercentage(address user) external view returns (uint256) {
        return lerpValue(tokenVesting, block.number.sub(stakes[user].depositBlock), INTERPOLATION_DIVISOR);
    }
    function getWithdrawablePercentage(address user) public view returns (uint256) {
        return lerpValue(withdrawalVesting, block.number.sub(stakes[user].withdrawBlock), INTERPOLATION_DIVISOR);
    }
    function getEmergencyWithdrawPenaltyPercentage(address user) external view returns (uint256) {
        // We could account for allowed withdrawal here, but it is likely to cause confusion. It is accounted for elsewhere.
        uint rawValue = lerpValue(emergencyWithdrawPenalty, block.number.sub(stakes[user].withdrawBlock), INTERPOLATION_DIVISOR);
        return rawValue;

        // IGNORED: adjust for allowed withdrawal
        //return rawValue.mul(INTERPOLATION_DIVISOR.sub(getWithdrawablePercentage(user))).div(INTERPOLATION_DIVISOR);

    }
    function getEmergencyWithdrawPenaltyAmountReturned(address user, uint256 _amount) public view returns (uint256) {
        // account for allowed withdrawal
        uint256 withdrawable = getWithdrawable(user);
        if (_amount <= withdrawable) {
            return _amount;
        }
        _amount = _amount.sub(withdrawable);
        return _amount.sub(lerpValue(emergencyWithdrawPenalty, block.number.sub(stakes[user].withdrawBlock), _amount)).add(withdrawable);
    }
}

