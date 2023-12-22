// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

/// @title VotingEscrow
/// @author Curve Finance
/// @notice Votes have a weight depending on time, so that users are
///         committed to the future of (whatever they are voting for)
/// @dev Vote weight decays linearly over time. Lock time cannot be
///      more than `MAXTIME` (4 years).
///  Voting escrow to have time-weighted votes
///  Votes have a weight depending on time, so that users are committed
///  to the future of (whatever they are voting for).
///  The weight in this implementation is linear, and lock cannot be more than maxtime:
///  w ^
///  1 +        /
///    |      /
///    |    /
///    |  /
///    |/
///  0 +--------+-----returns (time
///        maxtime (4 years?)
contract VotingEscrow is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    struct Point {
        int128 bias;
        int128 slope; // - dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }
    struct DepositedBalance {
        uint128 mcbAmount;
        uint128 muxAmount;
    }

    uint256 constant WEEK = 7 * 86400; // all future times are rounded by week
    uint256 constant MAXTIME = 4 * 364 * 86400; // 4 years - 4 days, aligned to 'WEEK'.
    uint256 constant MULTIPLIER = 10**18;

    address public mcbToken;
    address public muxToken;
    uint256 public supply;

    // Aragon's view methods for compatibility
    // address public controller;
    // bool public transfersEnabled;

    string public name;
    string public symbol;
    string public version;
    uint256 public constant decimals = 18;

    mapping(address => LockedBalance) public locked;
    mapping(address => DepositedBalance) public depositedBalances;

    uint256 public averageUnlockTime;
    uint256 public epoch;
    mapping(uint256 => Point) public pointHistory; // epoch returns (unsigned point
    mapping(address => Point[1000000000]) public userPointHistory; // user returns (Point[user_epoch]
    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges; // time returns (signed slope change

    // Checker for whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    mapping(address => bool) public isHandler;

    event Deposit(address indexed provider, address indexed token, uint256 value, uint256 indexed locktime, uint256 ts);
    event Withdraw(address indexed provider, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    // @notice Contract constructor
    // @param token_addr `ERC20CRV` token address
    // @param _name Token name
    // @param _symbol Token symbol
    // @param _version Contract version - required for Aragon compatibility
    function initialize(
        address _mcbToken,
        address _muxToken,
        string memory _name,
        string memory _symbol,
        string memory _version
    ) external initializer {
        __Ownable_init();

        mcbToken = _mcbToken;
        muxToken = _muxToken;
        pointHistory[0].blk = block.number;
        pointHistory[0].ts = _blockTime();
        // controller = msg.sender;
        // transfersEnabled = true;

        name = _name;
        symbol = _symbol;
        version = _version;
    }

    // @notice Apply setting external contract to check approved smart contract wallets
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    // @notice Get the most recently recorded rate of voting power decrease for `addr`
    // @param addr Address of the user wallet
    // @return Value of the slope
    function getLastUserSlope(address addr) external view returns (int128) {
        uint256 uepoch = userPointEpoch[addr];
        return userPointHistory[addr][uepoch].slope;
    }

    // @notice Get the most recently recorded rate of voting power decrease for `addr`
    // @param addr Address of the user wallet
    // @return Value of the slope
    function getLastUserBlock(address addr) external view returns (uint256) {
        uint256 uepoch = userPointEpoch[addr];
        return userPointHistory[addr][uepoch].blk;
    }

    // @notice Get the timestamp for checkpoint `_idx` for `_addr`
    // @param _addr User wallet address
    // @param _idx User epoch number
    // @return Epoch time of the checkpoint
    function userPointHistoryTime(address _addr, uint256 _idx) external view returns (uint256) {
        return userPointHistory[_addr][_idx].ts;
    }

    // @notice Get timestamp when `_addr`'s lock finishes
    // @param _addr User wallet
    // @return Epoch time of the lock end
    function lockedEnd(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    // @notice Get timestamp when `_addr`'s lock finishes
    // @param _addr User wallet
    // @return Epoch time of the lock end
    function lockedAmount(address _addr) external view returns (uint256) {
        return uint256(uint128(locked[_addr].amount));
    }

    // @notice Record global data to checkpoint
    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    // @notice Deposit `_value` tokens for `_addr` and add to the lock
    // @dev Anyone (even a smart contract) can deposit for someone else, but
    //         cannot extend their locktime and deposit for a brand new user
    // @param _addr User's wallet address
    // @param _value Amount to add to user's lock
    function depositFor(
        address _fundingAddr,
        address _addr,
        address _token,
        uint256 _value,
        uint256 _unlockTime
    ) external nonReentrant {
        _validateHandler();
        _deposit(_fundingAddr, _addr, _token, _value, _unlockTime);
    }

    // @notice Deposit `_value` tokens for `_addr` and add to the lock
    // @dev Anyone (even a smart contract) can deposit for someone else, but
    //         cannot extend their locktime and deposit for a brand new user
    // @param _addr User's wallet address
    // @param _value Amount to add to user's lock
    function deposit(
        address _token,
        uint256 _value,
        uint256 _unlockTime
    ) external nonReentrant {
        _deposit(msg.sender, msg.sender, _token, _value, _unlockTime);
    }

    function _deposit(
        address _fundingAddr,
        address _addr,
        address _token,
        uint256 _value,
        uint256 _unlockTime
    ) internal {
        LockedBalance storage _locked = locked[_addr];
        require(_token != address(0), "Invalid deposit token");
        require(_value > 0, "Value is zero"); // dev: need non-zero value
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK;
        require(unlockTime >= _locked.end, "Can only increase lock duration");

        if (_locked.amount == 0) {
            require(unlockTime > _blockTime(), "Can only lock until time in the future");
            require(unlockTime <= _blockTime() + MAXTIME, "Voting lock can be 4 years max");
        } else {
            require(_locked.end > _blockTime(), "Cannot add to expired lock. Withdraw");
        }
        _depositFor(_fundingAddr, _addr, _token, _value, unlockTime, _locked);
    }

    // @notice Extend the unlock time for `msg.sender` to `_unlockTime`
    // @param _unlockTime New epoch time for unlocking
    function increaseUnlockTime(uint256 _unlockTime) external nonReentrant {
        _increaseUnlockTime(msg.sender, _unlockTime);
    }

    function increaseUnlockTimeFor(address _addr, uint256 _unlockTime) external nonReentrant {
        _validateHandler();
        _increaseUnlockTime(_addr, _unlockTime);
    }

    function _increaseUnlockTime(address _addr, uint256 _unlockTime) internal {
        LockedBalance storage _locked = locked[_addr];
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK; // Locktime is rounded down to weeks
        require(_locked.end > _blockTime(), "Lock expired");
        require(_locked.amount > 0, "Nothing is locked");
        require(unlockTime >= _locked.end, "Can only increase lock duration");
        require(unlockTime <= _blockTime() + MAXTIME, "Voting lock can be 4 years max");
        _depositFor(_addr, _addr, address(0), 0, unlockTime, _locked);
    }

    function _updateAverageUnlockTime(
        uint256 _oldValue,
        uint256 _oldUnlockTime,
        uint256 _value,
        uint256 _unlockTime,
        uint256 _supplyBefore,
        uint256 _supply
    ) internal {
        // supply * (avgLockTime - now) + value * (unlock - now)
        // -----------------------------------------------------
        //                    total_supply
        uint256 _now = _blockTime();
        uint256 total = averageUnlockTime == 0 ? 0 : (averageUnlockTime - _now) * _supplyBefore;
        uint256 previous = _oldUnlockTime <= _now ? 0 : (_oldUnlockTime - _now) * _oldValue;
        uint256 next = (_unlockTime - _now) * _value;
        averageUnlockTime = _now + (total - previous + next) / _supply;
    }

    // @notice Deposit and lock tokens for a user
    // @param _addr User's wallet address
    // @param _value Amount to deposit
    // @param unlockTime New time when to unlock the tokens, or 0 if unchanged
    // @param locked_balance Previous locked amount / timestamp
    function _depositFor(
        address _fundingAddr,
        address _addr,
        address _token,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance storage lockedBalance
    ) internal {
        require(_token == address(0) || _token == mcbToken || _token == muxToken, "Not deposit token");

        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;

        LockedBalance memory oldLocked = lockedBalance;
        LockedBalance memory _locked = lockedBalance;
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += _safeI128(_value);
        if (_unlockTime != 0) {
            _locked.end = _unlockTime;
        }
        locked[_addr] = _locked;
        _updateAverageUnlockTime(
            _safeU256(oldLocked.amount),
            oldLocked.end,
            _safeU256(_locked.amount),
            _locked.end,
            supplyBefore,
            supply
        );

        // Possibilities:
        // Both oldLocked.end could be current or expired ( >/< _blockTime())
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > _blockTime() (always)
        _checkpoint(_addr, oldLocked, _locked);

        if (_value != 0) {
            IERC20Upgradeable(_token).safeTransferFrom(_fundingAddr, address(this), _value);
            if (_token == mcbToken) {
                depositedBalances[_addr].mcbAmount += uint128(_value);
            } else {
                depositedBalances[_addr].muxAmount += uint128(_value);
            }
        }

        emit Deposit(_addr, _token, _value, _locked.end, _blockTime());
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    // @notice Record global and per-user data to checkpoint
    // @param addr User's wallet address. No user checkpoint if 0x0
    // @param oldLocked Previous locked amount / end lock time for the user
    // @param newLocked New locked amount / end lock time for the user
    function _checkpoint(
        address addr,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint256 _epoch = epoch;

        if (addr != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (oldLocked.end > _blockTime() && oldLocked.amount > 0) {
                uOld.slope = oldLocked.amount / _safeI128(MAXTIME);
                uOld.bias = uOld.slope * _safeI128(oldLocked.end - _blockTime());
            }
            if (newLocked.end > _blockTime() && newLocked.amount > 0) {
                uNew.slope = newLocked.amount / _safeI128(MAXTIME);
                uNew.bias = uNew.slope * _safeI128(newLocked.end - _blockTime());
            }
            // Read values of scheduled changes in the slope
            // oldLocked.end can be in the past and in the future
            // newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[newLocked.end];
                }
            }
        }

        Point memory lastPoint = Point({ bias: 0, slope: 0, ts: _blockTime(), blk: block.number });
        if (_epoch > 0) {
            lastPoint = pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initialLastPoint = Point({
            bias: lastPoint.bias,
            slope: lastPoint.slope,
            ts: lastPoint.ts,
            blk: lastPoint.blk
        });

        uint256 block_slope = 0; // dblock/dt
        if (_blockTime() > lastPoint.ts) {
            block_slope = (MULTIPLIER * (block.number - lastPoint.blk)) / (_blockTime() - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; i++) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK;
                int128 d_slope = 0;
                if (t_i > _blockTime()) {
                    t_i = _blockTime();
                } else {
                    d_slope = slopeChanges[t_i];
                }
                lastPoint.bias -= lastPoint.slope * _safeI128(t_i - lastCheckpoint);
                lastPoint.slope += d_slope;
                if (lastPoint.bias < 0) {
                    // This can happen
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // This cannot happen - just in case
                    lastPoint.slope = 0;
                }
                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                lastPoint.blk = initialLastPoint.blk + (block_slope * (t_i - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (t_i == _blockTime()) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    pointHistory[_epoch] = lastPoint;
                }
            }
        }
        epoch = _epoch;
        // Now pointHistory is filled until t=now
        if (addr != address(0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }
        // Record the changed point into history
        pointHistory[_epoch] = lastPoint;

        if (addr != address(0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [newLocked.end]
            // and add old_user_slope to [oldLocked.end]
            if (oldLocked.end > _blockTime()) {
                // oldDslope was <something> - uOld.slope, so we cancel that
                oldDslope += uOld.slope;
                if (newLocked.end == oldLocked.end) {
                    oldDslope -= uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[oldLocked.end] = oldDslope;
            }

            if (newLocked.end > _blockTime()) {
                if (newLocked.end > oldLocked.end) {
                    newDslope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }
            // Now handle user history
            userPointEpoch[addr] = userPointEpoch[addr] + 1;
            uNew.ts = _blockTime();
            uNew.blk = block.number;
            userPointHistory[addr][userPointEpoch[addr]] = uNew;
        }
    }

    function withdraw() external nonReentrant {
        _withdrawFor(msg.sender);
    }

    function withdrawFor(address _addr) external nonReentrant {
        _validateHandler();
        _withdrawFor(_addr);
    }

    function _withdrawFor(address _addr) internal {
        LockedBalance storage _locked = locked[_addr];
        require(_blockTime() >= _locked.end, "The lock didn't expire");
        uint256 value = _safeU256(_locked.amount);

        LockedBalance memory oldLocked = _locked;
        _locked.end = 0;
        _locked.amount = 0;
        locked[_addr] = _locked;
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(_addr, oldLocked, _locked);
        uint256 mcbAmount = depositedBalances[_addr].mcbAmount;
        uint256 muxAmount = depositedBalances[_addr].muxAmount;
        depositedBalances[_addr].mcbAmount = 0;
        depositedBalances[_addr].muxAmount = 0;
        if (mcbAmount > 0) {
            IERC20Upgradeable(mcbToken).safeTransfer(_addr, mcbAmount);
        }
        if (muxAmount > 0) {
            IERC20Upgradeable(muxToken).safeTransfer(_addr, muxAmount);
        }

        emit Withdraw(_addr, value, _blockTime());
        emit Supply(supplyBefore, supplyBefore - value);
    }

    // The following IERC20Upgradeable/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    // @notice Binary search to estimate timestamp for block number
    // @param _block Block to find
    // @param maxEpoch Don't go beyond this epoch
    // @return Approximate timestamp for block
    function find_block_epoch(uint256 _block, uint256 maxEpoch) public view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = maxEpoch;
        for (uint256 i = 0; i < 128; i++) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function findTimestampEpoch(uint256 _timestamp) public view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = epoch;
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) break;
            uint256 _mid = (_min + _max + 2) / 2;
            if (pointHistory[_mid].ts <= _timestamp) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function findTimestampUserEpoch(
        address _addr,
        uint256 _timestamp,
        uint256 max_user_epoch
    ) public view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = max_user_epoch;
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) break;
            uint256 _mid = (_min + _max + 2) / 2;
            if (userPointHistory[_addr][_mid].ts <= _timestamp) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    // @notice Get the current voting power for `msg.sender`
    // @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    // @param addr User's wallet address
    // @return Voting power
    function balanceOf(address addr) public view returns (uint256) {
        return balanceOfWhen(addr, _blockTime());
    }

    // @notice Get the voting power for `msg.sender` at `_t` timestamp
    // @dev Adheres to the IERC20Upgradeable `balanceOf` interface for Aragon compatibility
    // @param addr User wallet address
    // @param _t Epoch time to return voting power at
    // @return User voting power
    function balanceOfWhen(address addr, uint256 _t) public view returns (uint256) {
        uint256 _epoch = userPointEpoch[addr];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory lastPoint = userPointHistory[addr][_epoch];
            lastPoint.bias -= lastPoint.slope * _safeI128(_t - lastPoint.ts);
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return _safeU256(lastPoint.bias);
        }
    }

    // @notice Measure voting power of `addr` at block height `_block`
    // @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    // @param addr User's wallet address
    // @param _block Block to calculate the voting power at
    // @return Voting power
    function balanceOfAt(address addr, uint256 _block) public view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        require(_block <= block.number);

        // Binary search
        uint256 _min = 0;
        uint256 _max = userPointEpoch[addr];
        // Will be always enough for 128-bit numbers
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[addr][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory upoint = userPointHistory[addr][_min];
        uint256 maxEpoch = epoch;
        uint256 _epoch = find_block_epoch(_block, maxEpoch);
        Point memory point_0 = pointHistory[_epoch];
        uint256 d_block = 0;
        uint256 d_t = 0;
        if (_epoch < maxEpoch) {
            Point memory point_1 = pointHistory[_epoch + 1];
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = block.number - point_0.blk;
            d_t = _blockTime() - point_0.ts;
        }
        uint256 block_time = point_0.ts;
        if (d_block != 0) {
            block_time += (d_t * (_block - point_0.blk)) / d_block;
        }
        upoint.bias -= upoint.slope * _safeI128(block_time - upoint.ts);
        if (upoint.bias >= 0) {
            return _safeU256(upoint.bias);
        } else {
            return 0;
        }
    }

    // @notice Calculate total voting power
    // @dev Adheres to the IERC20Upgradeable `totalSupply` interface for Aragon compatibility
    // @return Total voting power
    function totalSupply() external view returns (uint256) {
        Point storage lastPoint = pointHistory[epoch];
        return _supplyWhen(lastPoint, _blockTime());
    }

    // @notice Calculate total voting power
    // @dev Adheres to the IERC20Upgradeable `totalSupply` interface for Aragon compatibility
    // @return Total voting power
    function totalSupplyAt(uint256 _block) public view returns (uint256) {
        require(_block <= block.number);
        uint256 _epoch = epoch;
        uint256 target_epoch = find_block_epoch(_block, _epoch);

        Point storage point = pointHistory[target_epoch];
        uint256 dt = 0;
        if (target_epoch < _epoch) {
            Point storage pointNext = pointHistory[target_epoch + 1];
            if (point.blk != pointNext.blk) {
                dt = ((_block - point.blk) * (pointNext.ts - point.ts)) / (pointNext.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt = ((_block - point.blk) * (_blockTime() - point.ts)) / (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _supplyWhen(point, point.ts + dt);
    }

    // @notice Calculate total voting power
    // @dev Adheres to the IERC20Upgradeable `totalSupply` interface for Aragon compatibility
    // @return Total voting power
    function totalSupplyWhen(uint256 t) public view returns (uint256) {
        Point storage lastPoint = pointHistory[epoch];
        return _supplyWhen(lastPoint, t);
    }

    // @notice Calculate total voting power at some point in the past
    // @param point The point (bias/slope) to start search from
    // @param t Time to calculate the total voting power at
    // @return Total voting power at that time
    function _supplyWhen(Point storage point, uint256 t) internal view returns (uint256) {
        Point memory lastPoint = point;
        uint256 t_i = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; i++) {
            t_i += WEEK;
            int128 d_slope = 0;
            if (t_i > t) {
                t_i = t;
            } else {
                d_slope = slopeChanges[t_i];
            }
            lastPoint.bias -= lastPoint.slope * _safeI128(t_i - lastPoint.ts);
            if (t_i == t) {
                break;
            }
            lastPoint.slope += d_slope;
            lastPoint.ts = t_i;
        }
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return _safeU256(lastPoint.bias);
    }

    function _safeU256(int128 n) internal pure returns (uint256) {
        require(n >= 0, "n is negative");
        return uint256(uint128(n));
    }

    function _safeI128(uint256 n) internal pure returns (int128) {
        require(n <= uint128(type(int128).max), "n is negative");
        return int128(uint128(n));
    }

    function _blockTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "VotingEscrow: forbidden");
    }
}

