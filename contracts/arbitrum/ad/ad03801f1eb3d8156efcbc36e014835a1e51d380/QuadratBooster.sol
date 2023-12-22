// SPDX-License-Identifier: BUSL-1.1

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity 0.8.13;

import {     DepositInfo,     EnumerableSet,     IERC20,     IQuadratBoosterFactory,     Math,     PriorityQueue,     QuadratBoosterStorage,     SafeCast,     SafeERC20 } from "./QuadratBoosterStorage.sol";

contract QuadratBooster is QuadratBoosterStorage {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PriorityQueue for PriorityQueue.Heap;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Deposits user amount. Time locked optionally.
     * @param _amount to be staked
     * @param _timeLockBlocks The numbers of blocks to lock the deposit.
     * @notice [_timeLockBlocks] is restricted by contract owner settings.
     * Set _timeLockBlocks to zero for usual deposit.
     */
    function deposit(uint256 _amount, uint32 _timeLockBlocks)
        external
        nonReentrant
    {
        require(_amount >= Math.max(1, minimalDepositAmount), "MDA");
        address _sender = _msgSender();
        uint256 blockNumber = block.number;
        DepositInfo storage _deposit = deposits[_sender];
        require(blockNumber < toBlock, "BN");
        require(
            (_timeLockBlocks == 0 && _deposit.timedAmount == 0) ||
                (_timeLockBlocks != 0 &&
                    timedBonus(_timeLockBlocks) != 0 &&
                    _deposit.amount == 0),
            "TB"
        );
        uint256 _rewardAmount = _claimReward(_sender);
        uint256 _blockAmount = __getBlockAmount(_amount);
        uint256 _timedAmount = __getTimedAmount(_amount, _timeLockBlocks);
        _deposit.amount += _amount;
        _deposit.blockAmount += _blockAmount;
        _deposit.timedAmount += _timedAmount;
        totalDeposit += _amount;
        uint256 _virtualDeposit = _amount + _blockAmount + _timedAmount;
        virtualTotalDeposit += _virtualDeposit;
        uint256 _firstWithdrawBlockNumber = blockNumber +
            Math.max(minimalWithdrawBlocks, _timeLockBlocks);
        _deposit.firstWithdrawBlockNumber = _firstWithdrawBlockNumber
            .toUint64();
        if (_timeLockBlocks > 0) {
            _timedAmounts.enqueue(_firstWithdrawBlockNumber, _timedAmount);
        }
        __safeTransferFrom(depositToken, _sender, address(this), _amount);
        _depositors.add(_sender);
        IQuadratBoosterFactory(factory).addUserBooster(_sender);
        emit Deposit(_sender, _amount, _virtualDeposit, _rewardAmount);
    }

    /**
     * @dev Withdraws user amount.
     * @notice If amount equal zero then the position will be closed
     * @param _amount to be withdrawn
     */
    function withdraw(uint256 _amount) external nonReentrant {
        DepositInfo storage _deposit = deposits[_msgSender()];
        uint256 _userAmount = _deposit.amount;
        require(_amount <= _userAmount, "UA");
        require(
            block.number >= _deposit.firstWithdrawBlockNumber ||
                _rewardUnlocked() == 0,
            "MWBN"
        );
        uint256 _blockAmount = (_deposit.blockAmount * _amount) / _userAmount;
        if (_amount == 0) {
            _amount = _userAmount;
            _blockAmount = _deposit.blockAmount;
        }
        address _sender = _msgSender();
        uint256 _rewardAmount = _claimReward(_sender);
        _deposit.amount -= _amount;
        _deposit.blockAmount -= _blockAmount;
        totalDeposit -= _amount;
        virtualTotalDeposit -= _amount + _blockAmount;
        __safeTransferFrom(depositToken, address(this), _sender, _amount);
        if (_deposit.amount == 0) {
            _depositors.remove(_sender);
            IQuadratBoosterFactory(factory).removeUserBooster(_sender);
        } else {
            require(
                _deposit.amount >= Math.max(1, minimalDepositAmount),
                "MDA"
            );
        }
        emit Withdraw(_sender, _amount, _rewardAmount);
    }

    /**
     * @dev Withdraws user reward.
     */
    function claimReward() external nonReentrant {
        uint256 _rewardAmount = _claimReward(_msgSender());
        require(_rewardAmount > 0, "RA");
        emit ClaimReward(msg.sender, _rewardAmount);
    }

    /**
     * @dev Calculates user reward.
     * @param user address
     * @return _rewardAmount
     */
    function userReward(address user)
        public
        view
        returns (uint256 _rewardAmount)
    {
        DepositInfo storage _deposit = deposits[user];
        _rewardAmount = _userReward(_deposit, calculateCumulativeReward());
    }

    function _claimReward(address user)
        internal
        returns (uint256 _rewardAmount)
    {
        DepositInfo storage _deposit = deposits[user];
        uint256 _cumulativeRewardPerShare = updateCumulativeReward();
        _rewardAmount += _userReward(_deposit, _cumulativeRewardPerShare);
        _deposit.cumulativeRewardPerShare = _cumulativeRewardPerShare;
        if (
            _deposit.timedAmount > 0 &&
            block.number >= _deposit.firstWithdrawBlockNumber
        ) {
            _deposit.timedAmount = 0;
        }

        if (_rewardAmount > 0) {
            require(
                rewardToken.balanceOf(address(this)) >= _rewardAmount,
                "RB"
            );
            _deposit.claimedReward += _rewardAmount;
            rewardClaimed += _rewardAmount;
            __safeTransferFrom(rewardToken, address(this), user, _rewardAmount);
        }
    }

    function _userReward(
        DepositInfo storage _deposit,
        uint256 _cumulativeRewardPerShare
    ) internal view returns (uint256 _rewardAmount) {
        if (_deposit.amount > 0) {
            _rewardAmount = __userReward(
                _deposit.amount + _deposit.blockAmount,
                _cumulativeRewardPerShare - _deposit.cumulativeRewardPerShare
            );
            if (_deposit.timedAmount > 0) {
                if (block.number < _deposit.firstWithdrawBlockNumber) {
                    _rewardAmount += __userReward(
                        _deposit.timedAmount,
                        _cumulativeRewardPerShare -
                            _deposit.cumulativeRewardPerShare
                    );
                } else {
                    _rewardAmount += __userReward(
                        _deposit.timedAmount,
                        cumulativeRewardPerShares[
                            _deposit.firstWithdrawBlockNumber
                        ] - _deposit.cumulativeRewardPerShare
                    );
                }
            }
        }
    }

    function __safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) private {
        uint256 fromBalance = token.balanceOf(from);
        uint256 toBalance = token.balanceOf(to);
        if (from == address(this)) {
            token.safeTransfer(to, amount);
        } else {
            token.safeTransferFrom(from, to, amount);
        }
        require(fromBalance - token.balanceOf(from) == amount, "BFB");
        require(token.balanceOf(to) - toBalance == amount, "BTB");
    }

    function __getBlockAmount(uint256 _amount)
        private
        view
        returns (uint256 _blockAmount)
    {
        if (block.number <= _bonusBlockNumber) {
            _blockAmount = (_amount * _blockBonus) / ONE_HUNDRED;
        }
    }

    function __getTimedAmount(uint256 _amount, uint32 _timeLockBlocks)
        private
        view
        returns (uint256 _timedAmount)
    {
        _timedAmount = (_amount * timedBonus(_timeLockBlocks)) / ONE_HUNDRED;
    }

    function __userReward(uint256 amount, uint256 _cumulativeRewardPerShare)
        private
        pure
        returns (uint256 _rewardAmount)
    {
        _rewardAmount = (amount * _cumulativeRewardPerShare) / MULTIPLIER;
    }
}

