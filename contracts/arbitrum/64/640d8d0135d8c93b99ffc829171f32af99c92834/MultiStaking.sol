// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import { OnlyWhitelisted } from "./OnlyWhitelisted.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeMath } from "./SafeMath.sol";
import { Math } from "./Math.sol";
import { Interpolating } from "./Interpolating.sol";
import { UserStake, IMultiStaking } from "./IMultiStaking.sol";
import { ISnapshottable } from "./ISnapshottable.sol";
import { IStakingPerStakeValuator } from "./IStakingPerStakeValuator.sol";
//import { SafeERC20 } from '../libraries/SafeERC20.sol';
import { SafeERC20 } from "./SafeERC20.sol";


contract MultiStaking is OnlyWhitelisted, Interpolating, IStakingPerStakeValuator {
    using SafeMath for uint256;

    // the amount of the tokens used for calculation may need to mature over time
    Interpolation public tokenVesting;
    // over time some of the tokens may be available for early withdrawal
    Interpolation public withdrawalVesting;
    // there may be a penalty for withdrawing everything early
    Interpolation public emergencyWithdrawPenaltyVesting;

    mapping(IERC20 => bool) public isTokenWhitelisted;
    mapping(IERC20 => uint256) public minimumStakeToBeListed;

    // token => user => data
    mapping(IERC20 => mapping(address => UserStake)) public stakes;
    // token => 
    mapping(IERC20 => address[]) public stakers;
    // token => 
    mapping(address => bool) public isPenaltyCollector;

    // token => user => bool
    mapping(IERC20 => mapping(address => bool)) inTokenStakers;
    // user => bool
    mapping(address => bool) public inAllStakers;
    address[] public allStakers;
    mapping(address => IERC20[]) public userTokens;

    IERC20 public baseToken;

    // what tokens are active in the contract
    IERC20[] public tokens;
    mapping(IERC20 => bool) public isTokenAdded;

    // how much penalty is available to withdraw per token
    mapping(IERC20 => uint256) public penalty;
    //uint256 public minimumStakeToBeListed; // how much token is required to be listed in the stakers variable

    uint256[] public snapshotBlockNumbers;
    // blockNumber => user => => token => amount
    mapping(uint256 => mapping(address => mapping(IERC20 => uint256))) public snapshots;
    // blockNumber => bool
    mapping(uint256 => bool) public snapshotExists;
    // user => blockNumber
    mapping(address => uint256) public lastSnapshotBlockNumbers;

    uint8 public WITHDRAWER_TIER;
    uint8 public MIGRATOR_TIER;
    uint8 public TOKEN_WHITELISTER_TIER;
    uint8 public SNAPSHOTTER_TIER;
    uint8 public PENALTY_COLLECTOR_TIER;

    event Staked(address indexed account, IERC20 token, uint256 amount, uint256 stakingTime);
    event Withdrawn(address indexed account, IERC20 token, uint256 amount);
    event EmergencyWithdrawn(address indexed account, IERC20 token, uint256 amount, uint256 penalty);
    event Migrated(address indexed account, IERC20 token, uint256 amount, address destination);
    event TokenWhitelistChanged(IERC20 indexed token, bool state);
    event Snapshot(uint256 blockNumber);


    constructor(IERC20 _token, uint256 vestingLength, uint256 _minimumStakeToBeListed) {
        require(address(_token) != address(0), "Token address cannot be 0x0");

        // eliminate the possibility of a real snapshot at idx 0
        snapshotBlockNumbers.push(0);

        baseToken = _token;
        trackToken(_token);
        isTokenWhitelisted[_token] = true;
        minimumStakeToBeListed[_token] = _minimumStakeToBeListed;

        // by default emergency withdrawal penalty matures from 80% to 0%
        setEmergencyWithdrawPenalty(Interpolation(0, vestingLength, INTERPOLATION_DIVISOR.mul(8).div(10), 0));
        // by default withdrawals mature from 0% to 100%
        setWithdrawalVesting(Interpolation(0, vestingLength, 0, INTERPOLATION_DIVISOR));
        // by default calculation token amount is fully mature immediately
        setTokenVesting(Interpolation(0, 0, INTERPOLATION_DIVISOR, INTERPOLATION_DIVISOR));

        WITHDRAWER_TIER = consumeNextId();
        MIGRATOR_TIER = consumeNextId();
        TOKEN_WHITELISTER_TIER = consumeNextId();
        SNAPSHOTTER_TIER = consumeNextId();
        PENALTY_COLLECTOR_TIER = consumeNextId();
    }


    ///////////////////////////////////////
    // Core functionality
    ///////////////////////////////////////

    function getStake(address _account, IERC20 _token) public view returns (UserStake memory) {
        return stakes[_token][_account];
    }
    function stake(IERC20 _token, uint256 _amount) public {
        return _stake(msg.sender, msg.sender, _token, _amount);
    }
    function stakeFor(address _account, uint256 _amount) public {
        return stakeFor(_account, baseToken, _amount);
    }
    function stakeFor(address _account, IERC20 _token, uint256 _amount) public {
        return _stake(msg.sender, _account, _token, _amount);
    }
    function _stake(address from, address account, IERC20 _token, uint256 amount) internal tokenIsWhitelisted(_token) {
        require(amount > 0, "Amount must be greater than 0");

        trackToken(_token);

        _updateSnapshots(0, type(uint256).max, account);

        uint256 allowance = _token.allowance(from, address(this));
        require(allowance >= amount, "Check the token allowance");

        UserStake memory userStake = stakes[_token][account];
        uint256 preStakeAmount = userStake.amount;

        // to prevent dust attacks, only add user as staker if they cross the stake threshold
        uint256 minimum = minimumStakeToBeListed[_token];
        if (minimum == 0) {
            minimum = (10**IERC20Metadata(address(_token)).decimals()).div(100); // 1%
        }
        if (preStakeAmount.add(amount) >= minimum) {
            // ensure user isn't already in the list
            if (!inTokenStakers[_token][account]) {
                // track which tokens are relevant for a user
                userTokens[account].push(_token);

                // track which addresses are staking for a token
                stakers[_token].push(account);

                inTokenStakers[_token][account] = true;
            }

            if (!inAllStakers[account]) {
                allStakers.push(account);
                inAllStakers[account] = true;
            }
        }

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
            userStake.depositBlock =             lerp(0, userStake.amount.add(amount), userStake.depositBlock,             block.number, userStake.amount);
            userStake.withdrawBlock =            lerp(0, userStake.amount.add(amount), userStake.withdrawBlock,            block.number, userStake.amount);
            userStake.emergencyWithdrawalBlock = lerp(0, userStake.amount.add(amount), userStake.emergencyWithdrawalBlock, block.number, userStake.amount);
            userStake.amount = userStake.amount.add(amount);
        }
        stakes[_token][account] = userStake;

        emit Staked(account, _token, amount, block.timestamp);

        SafeERC20.safeTransferFrom(_token, from, address(this), amount);
    }

    function updateSnapshots(uint256 startIdx, uint256 endIdx) external {
        _updateSnapshots(startIdx, endIdx, msg.sender);
    }
    function _updateSnapshots(uint256 startIdx, uint256 endIdx, address account) internal {
        if (snapshotBlockNumbers.length == 0) {
            return; // early abort
        }

        require(endIdx > startIdx, "endIdx must be greater than startIdx");
        uint256 lastSnapshotBlockNumber = lastSnapshotBlockNumbers[account];
        uint256 lastBlockNumber = snapshotBlockNumbers[uint256(snapshotBlockNumbers.length).sub(1)];

        // iterate backwards through snapshots
        if (snapshotBlockNumbers.length < endIdx) {
            endIdx = uint256(snapshotBlockNumbers.length).sub(1);
        }
        // ensure snapshots aren't skipped
        require(startIdx == 0 || snapshotBlockNumbers[startIdx.sub(1)] <= lastSnapshotBlockNumber, "Can't skip snapshots");
        for (uint256 i = endIdx;  i > startIdx;  --i) {
            uint256 blockNumber = snapshotBlockNumbers[i];

            if (lastSnapshotBlockNumber >= blockNumber) {
                break; // done with user
            }

            // user => token => amount
            mapping(address => mapping(IERC20 => uint256)) storage _snapshot = snapshots[blockNumber];

            // for each token, update the vested amount
            IERC20[] memory _userTokens = userTokens[account];
            for (uint256 j = 0;  j < _userTokens.length;  ++j) {
                IERC20 _token = _userTokens[j];
                _snapshot[account][_token] = _calculateVestedTokensAt(account, _token, blockNumber);
            }
        }

        // set user as updated
        lastSnapshotBlockNumbers[account] = lastBlockNumber;
    }
    function snapshot() external onlyWhitelistedTier(SNAPSHOTTER_TIER) {
        if (!snapshotExists[block.number]) {
            snapshotBlockNumbers.push(block.number);
            snapshotExists[block.number] = true;
            emit Snapshot(block.number);
        }
    }
    function withdraw(IERC20 _token, uint256 _amount) public {
        _updateSnapshots(0, type(uint256).max, msg.sender);
        return _withdraw(msg.sender, _token, _amount, true, msg.sender);
    }
    function withdrawFor(address[] memory _account, IERC20 _token, uint256[] memory _amount) external onlyWhitelistedTier(WITHDRAWER_TIER) {
        require(_account.length == _amount.length, "Account and amount arrays must be the same length");
        for (uint256 i = 0;  i < _account.length;  ++i) {
            _updateSnapshots(0, type(uint256).max, _account[i]);
            _withdraw(_account[i], _token, _amount[i], false, _account[i]);
        }
    }
    function migrateFor(address[] memory _account, IERC20 _token, uint256[] memory _amount, address _destination) external onlyWhitelistedTier(MIGRATOR_TIER) {
        require(_account.length == _amount.length, "Account and amount arrays must be the same length");
        for (uint256 i = 0;  i < _account.length;  ++i) {
            _updateSnapshots(0, type(uint256).max, _account[i]);
            _withdraw(_account[i], _token, _amount[i], false, _destination);
        }
    }
    function _withdraw(address _account, IERC20 _token, uint256 _amount, bool _respectLimits, address _destination) internal {
        require(_amount > 0, "Amount must be greater than 0");

        // cap to deal with frontend rounding errors
        UserStake memory userStake = stakes[_token][_account];
        if (userStake.amount < _amount) {
            _amount = userStake.amount;
        }

        uint256 withdrawableAmount = getWithdrawable(_account, _token);
        if (!_respectLimits) {
            // if we don't respect limits, we can withdraw the entire user's amount
            withdrawableAmount = userStake.amount;
        }
        require(withdrawableAmount >= _amount, "Insufficient withdrawable balance");

        userStake.amount = userStake.amount.sub(_amount);
        uint256 endBlock = Math.min(block.number, userStake.withdrawBlock.add(withdrawalVesting.endOffset));
        userStake.withdrawBlock = lerp(0, withdrawableAmount, userStake.withdrawBlock, endBlock, _amount);
        stakes[_token][_account] = userStake;

        if (_destination != _account) {
            // the user was migrated, not withdrawn
            emit Migrated(_account, _token, _amount, _destination);
        } else {
            emit Withdrawn(_account, _token, _amount);
        }

        SafeERC20.safeTransfer(_token, _destination, _amount);
    }

    function emergencyWithdraw(IERC20 _token, uint256 _amount) public {
        return _emergencyWithdraw(msg.sender, _token, _amount);
    }
    function _emergencyWithdraw(address account, IERC20 _token, uint256 _amount) internal {
        require(_amount > 0, "Amount must be greater than 0");

        // cap to deal with frontend rounding errors
        UserStake memory userStake = stakes[_token][account];
        if (userStake.amount < _amount) {
            _amount = userStake.amount;
        }

        // max out the normal withdrawable first out of respect for the user
        uint256 withdrawableAmount = getWithdrawable(account, _token);
        if (withdrawableAmount > 0) {
            if (withdrawableAmount >= _amount) {
                return _withdraw(account, _token, _amount, true, account);
            } else {
                _withdraw(account, _token, withdrawableAmount, true, account);
                _amount = _amount.sub(withdrawableAmount);
            }
            // update data after the withdraw
            userStake = stakes[_token][account];
        }

        // figure out the numbers for the emergency withdraw
        require(userStake.amount <= _amount, "Insufficient emergency-withdrawable balance");
        userStake.amount = userStake.amount.sub(_amount);
        uint256 returnedAmount = getEmergencyWithdrawPenaltyAmountReturned(account, _token, _amount);
        uint256 _penalty = _amount.sub(returnedAmount);
        uint256 endBlock = Math.min(block.number, userStake.emergencyWithdrawalBlock.add(emergencyWithdrawPenaltyVesting.endOffset));
        userStake.emergencyWithdrawalBlock = lerp(0, userStake.amount, userStake.emergencyWithdrawalBlock, endBlock, _amount);

        // account for the penalty
        penalty[_token] = penalty[_token].add(_penalty);
        stakes[_token][account] = userStake;

        emit EmergencyWithdrawn(account, _token, _amount, _penalty);

        SafeERC20.safeTransfer(_token, account, returnedAmount);
    }


    ///////////////////////////////////////
    // Housekeeping
    ///////////////////////////////////////

    function trackToken(IERC20 _token) internal {
        if (!isTokenAdded[_token]) {
            tokens.push(_token);
            isTokenAdded[_token] = true;
        }
    }
    modifier tokenIsWhitelisted(IERC20 _token) {
        require(isTokenWhitelisted[IERC20(address(0))] || isTokenWhitelisted[_token], "Token is not whitelisted");
        _;
    }
    function setTokenWhitelist(IERC20[] memory _token, bool[] memory _state, uint256[] memory _minimumStakeToBeListed) external onlyWhitelistedTier(TOKEN_WHITELISTER_TIER) {
        require(_token.length == _state.length, "Token and state arrays must be the same length");
        for (uint256 i = 0;  i < _token.length;  ++i) {
            IERC20 token_ = _token[i];
            isTokenWhitelisted[token_] = _state[i];
            minimumStakeToBeListed[token_] = _minimumStakeToBeListed[i];

            trackToken(token_);

            emit TokenWhitelistChanged(token_, _state[i]);
        }
    }
    function setTokenVesting(Interpolation memory _value) public onlyOwner {
        tokenVesting = _value;
    }
    function setWithdrawalVesting(Interpolation memory _value) public onlyOwner {
        withdrawalVesting = _value;
    }
    function setEmergencyWithdrawPenalty(Interpolation memory _value) public onlyOwner {
        emergencyWithdrawPenaltyVesting = _value;
    }
    function sendPenalty(address to, IERC20 _token) external onlyWhitelistedTier(PENALTY_COLLECTOR_TIER) returns (uint256) {
        uint256 _amount = penalty[_token];
        penalty[_token] = 0;

        SafeERC20.safeTransfer(_token, to, _amount);

        return _amount;
    }
    /*
    function setMinimumStakeToBeListed(uint256 _minimumStakeToBeListed) external onlyOwner {
        minimumStakeToBeListed = _minimumStakeToBeListed;
    }
    */
    function getAllStakers() external view returns (address[] memory) {
        return allStakers;
    }
    function getStakersCount() external view returns (uint256) {
        return allStakers.length;
    }
    function getStakersCount(IERC20 _token) external view returns (uint256) {
        return stakers[_token].length;
    }
    function getStakers(uint256 idx) external view returns (address) {
        return allStakers[idx];
    }
    function getStakers(IERC20 _token, uint256 idx) external view returns (address) {
        return stakers[_token][idx];
    }


    ///////////////////////////////////////
    // View functions
    ///////////////////////////////////////

    function getAllTokens() external view returns (IERC20[] memory) {
        return tokens;
    }
    function tokensLength() external view returns (uint256) {
        return tokens.length;
    }
    function isAllTokensWhitelisted() external view returns (bool) {
        return isTokenWhitelisted[IERC20(address(0))];
    }
    function getUserTokens(address _user) external view returns (IERC20[] memory) {
        IERC20[] memory result = userTokens[_user];
        if (result.length == 0) {
            // default to baseToken
            result = new IERC20[](1);
            result[0] = baseToken;
        }
        return result;
    }
    function token() external view returns (IERC20) {
        return baseToken;
    }
    function _calculateVestedTokensAt(address user, IERC20 _token, uint256 blockNumber) internal view returns (uint256 result) {
        if (blockNumber < stakes[_token][user].depositBlock) {
            // ideally this should never happen but as a safety precaution..
            return 0;
        }

        return lerpValue(tokenVesting, blockNumber.sub(stakes[_token][user].depositBlock), stakes[_token][user].amount);
    }
    function getVestedTokensAtSnapshot(address user, IERC20 _token, uint256 blockNumber) external view returns (uint256) {
        // we don't enforce snapshots, to avoid breaking things completely in case of an issue
        //require(snapshotExists[blockNumber], "No snapshot exists for this block");

        // is the user snapshotted for this?
        if (lastSnapshotBlockNumbers[user] >= blockNumber) {
            // use the snapshot
            return snapshots[blockNumber][user][_token];
        }

        // no snapshot so we calculate the snapshot as it would have been at that time in the past
        return _calculateVestedTokensAt(user, _token, blockNumber);
    }
    function getVestedTokens(address user, IERC20 _token) external view returns (uint256) {
        return _calculateVestedTokensAt(user, _token, block.number);
    }
    function getWithdrawable(address user, IERC20 _token) public view returns (uint256) {
        return lerpValue(withdrawalVesting, block.number.sub(stakes[_token][user].withdrawBlock), stakes[_token][user].amount);
    }
    function getTotalStake(address user, IERC20 _token) public view returns (uint256) {
        return stakes[_token][user].amount;
    }
    function getEmergencyWithdrawPenalty(address user, IERC20 _token) external view returns (uint256) {
        // account for allowed withdrawal
        uint256 _amount = stakes[_token][user].amount;
        uint256 withdrawable = getWithdrawable(user, _token);
        if (_amount <= withdrawable) {
            return 0;
        }
        _amount = _amount.sub(withdrawable);
        return lerpValue(emergencyWithdrawPenaltyVesting, block.number.sub(stakes[_token][user].withdrawBlock), _amount);
    }
    function getVestedTokensPercentage(address user, IERC20 _token) public view returns (uint256) {
        return lerpValue(tokenVesting, block.number.sub(stakes[_token][user].depositBlock), INTERPOLATION_DIVISOR);
    }
    function getWithdrawablePercentage(address user, IERC20 _token) public view returns (uint256) {
        return lerpValue(withdrawalVesting, block.number.sub(stakes[_token][user].withdrawBlock), INTERPOLATION_DIVISOR);
    }
    function getEmergencyWithdrawPenaltyPercentage(address user, IERC20 _token) public view returns (uint256) {
        // We could account for allowed withdrawal here, but it is likely to cause confusion. It is accounted for elsewhere.
        uint rawValue = lerpValue(emergencyWithdrawPenaltyVesting, block.number.sub(stakes[_token][user].withdrawBlock), INTERPOLATION_DIVISOR);
        return rawValue;

        // IGNORED: adjust for allowed withdrawal
    }
    function getEmergencyWithdrawPenaltyAmountReturned(address user, IERC20 _token, uint256 _amount) public view returns (uint256) {
        // account for allowed withdrawal
        uint256 withdrawable = getWithdrawable(user, _token);
        if (_amount <= withdrawable) {
            return _amount;
        }
        _amount = _amount.sub(withdrawable);
        return _amount.sub(lerpValue(emergencyWithdrawPenaltyVesting, block.number.sub(stakes[_token][user].withdrawBlock), _amount)).add(withdrawable);
    }
}
