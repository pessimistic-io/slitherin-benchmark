// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./LibDiamond.sol";
import "./SafeCast.sol";
import "./AccessControlUpgradeable.sol";
import "./IUniswapV2Router02.sol";
import "./IDividendPayingToken.sol";
import "./IVestingSchedule.sol";
import "./console.sol";

contract WithReward is
    WithStorage,
    AccessControlUpgradeable,
    IDividendPayingToken
{
    event Claim(
        address indexed account,
        uint256 amount,
        bool indexed automatic
    );

    // ==================== Errors ==================== //

    error InvalidClaimTime();
    error NoSupply();
    error NullAddress();

    // ==================== Events ==================== //

    event UpdateRewardToken(address token);
    event RewardProcessed(
        address indexed owner,
        uint256 value,
        address indexed token
    );

    function __WithReward_init() internal onlyInitializing {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // configure excluded from fee role
        _grantRole(LibDiamond.EXCLUDED_FROM_FEE_ROLE, _msgSender());
        _grantRole(LibDiamond.EXCLUDED_FROM_FEE_ROLE, address(this));
        _grantRole(LibDiamond.EXCLUDED_FROM_FEE_ROLE, _ds().liquidityWallet); // protocol added liquidity
        _grantRole(
            LibDiamond.EXCLUDED_FROM_FEE_ROLE,
            0x926C609Cb956b1463d964855D63a89cBBE3aC8c0
        ); // locked liquidity
        _grantRole(
            LibDiamond.EXCLUDED_FROM_FEE_ROLE,
            0xEDe91c7107ab0588232048Dab0163832E960865d
        ); // marketing wallet
        _grantRole(
            LibDiamond.EXCLUDED_FROM_FEE_ROLE,
            0xC55f51d8bf79651213603fd21e35C635D0E295e2
        ); // treasury wallet
        _grantRole(
            LibDiamond.EXCLUDED_FROM_FEE_ROLE,
            0x9c0A0447C5b77edbf4e84cE0f104b5364537B0be
        ); // ecosystem wallet

        // configure excluded from antiwhale role
        _grantRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, _msgSender());
        _grantRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, address(this));
        _grantRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, address(0));
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            LibDiamond.BURN_ADDRESS
        );
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            _ds().liquidityWallet
        );
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            0x926C609Cb956b1463d964855D63a89cBBE3aC8c0
        ); // locked liquidity
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            0xEDe91c7107ab0588232048Dab0163832E960865d
        ); // marketing wallet
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            0xC55f51d8bf79651213603fd21e35C635D0E295e2
        ); // treasury wallet
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            0x9c0A0447C5b77edbf4e84cE0f104b5364537B0be
        ); // ecosystem wallet

        _grantRole(LibDiamond.EXCLUDED_FROM_REWARD_ROLE, _msgSender());
        _grantRole(LibDiamond.EXCLUDED_FROM_REWARD_ROLE, address(this));
        _grantRole(LibDiamond.EXCLUDED_FROM_REWARD_ROLE, address(0));
        _grantRole(
            LibDiamond.EXCLUDED_FROM_REWARD_ROLE,
            LibDiamond.BURN_ADDRESS
        );
        _grantRole(
            LibDiamond.EXCLUDED_FROM_REWARD_ROLE,
            0x926C609Cb956b1463d964855D63a89cBBE3aC8c0
        ); // locked liquidity
        _grantRole(
            LibDiamond.EXCLUDED_FROM_REWARD_ROLE,
            0xC55f51d8bf79651213603fd21e35C635D0E295e2
        ); // treasury wallet
        _grantRole(
            LibDiamond.EXCLUDED_FROM_REWARD_ROLE,
            0x9c0A0447C5b77edbf4e84cE0f104b5364537B0be
        ); // ecosystem wallet
    }

    function claimRewards(bool goHam) external {
        _processAccount(_msgSender(), goHam);
    }

    // ==================== DividendPayingToken ==================== //

    /// @return dividends The amount of reward in wei that `_owner` can withdraw.
    function dividendOf(address _owner)
        public
        view
        returns (uint256 dividends)
    {
        return withdrawableDividendOf(_owner);
    }

    /// @return dividends The amount of rewards that `_owner` has withdrawn
    function withdrawnDividendOf(address _owner)
        public
        view
        returns (uint256 dividends)
    {
        return _rs().withdrawnReward[_owner];
    }

    /// The total accumulated rewards for a address
    function accumulativeDividendOf(address _owner)
        public
        view
        returns (uint256 accumulated)
    {
        return
            SafeCast.toUint256(
                SafeCast.toInt256(
                    _rs().magnifiedRewardPerShare * rewardBalanceOf(_owner)
                ) + _rs().magnifiedReward[_owner]
            ) / LibDiamond.MAGNITUDE;
    }

    /// The total withdrawable rewards for a address
    function withdrawableDividendOf(address _owner)
        public
        view
        returns (uint256 withdrawable)
    {
        return accumulativeDividendOf(_owner) - _rs().withdrawnReward[_owner];
    }

    // ==================== Views ==================== //

    function getRewardToken()
        public
        view
        returns (
            address token,
            address router,
            address[] memory path
        )
    {
        LibDiamond.RewardToken memory rewardToken = _rs().rewardToken;
        return (rewardToken.token, rewardToken.router, rewardToken.path);
    }

    function rewardBalanceOf(address account) public view returns (uint256) {
        return _rs().rewardBalances[account];
    }

    function totalRewardSupply() public view returns (uint256) {
        return _rs().totalRewardSupply;
    }

    function isExcludedFromRewards(address account) public view returns (bool) {
        return hasRole(LibDiamond.EXCLUDED_FROM_REWARD_ROLE, account);
    }

    /// Gets the index of the last processed wallet
    /// @return index The index of the last wallet that was paid rewards
    function getLastProcessedIndex() external view returns (uint256 index) {
        return _rs().lastProcessedIndex;
    }

    /// @return numHolders The number of reward tracking token holders
    function getRewardHolders() external view returns (uint256 numHolders) {
        return _rs().rewardHolders.keys.length;
    }

    /// Gets reward account information by address
    function getRewardAccount(address _account)
        public
        view
        returns (
            address account,
            int256 index,
            int256 numInQueue,
            uint256 withdrawableRewards,
            uint256 totalRewards,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 timeTillAutoClaim,
            bool manualClaim
        )
    {
        account = _account;
        index = getIndexOfKey(account);
        if (index < 0) {
            return (account, -1, 0, 0, 0, 0, 0, 0, false);
        }

        uint256 lastProcessedIndex = _rs().lastProcessedIndex;

        numInQueue = 0;
        if (uint256(index) > lastProcessedIndex) {
            numInQueue = index - int256(lastProcessedIndex);
        } else {
            uint256 holders = _rs().rewardHolders.keys.length;
            uint256 processesUntilEndOfArray = holders > lastProcessedIndex
                ? holders - lastProcessedIndex
                : 0;
            numInQueue = index + int256(processesUntilEndOfArray);
        }
        withdrawableRewards = withdrawableDividendOf(account);
        totalRewards = accumulativeDividendOf(account);
        lastClaimTime = _rs().claimTimes[account];
        manualClaim = _rs().manualClaim[account];
        nextClaimTime = lastClaimTime > 0
            ? lastClaimTime + _rs().claimTimeout
            : 0;
        timeTillAutoClaim = nextClaimTime > block.timestamp
            ? nextClaimTime - block.timestamp
            : 0;
    }

    // ==================== Management ==================== //

    /// @notice Adds incoming funds to the rewards per share
    function accrueReward() internal {
        uint256 rewardSupply = totalRewardSupply();
        if (rewardSupply <= 0) revert NoSupply();

        uint256 balance = address(this).balance;
        if (balance > 0) {
            _rs().magnifiedRewardPerShare +=
                (balance * LibDiamond.MAGNITUDE) /
                rewardSupply;
            _rs().totalAccruedReward += balance;
        }
    }

    // Vesting contract can update reward balance of account
    function updateRewardBalance(address account, uint256 balance)
        public
        onlyRole(LibDiamond.VESTING_ROLE)
    {
        _setRewardBalance(account, balance);
    }

    /// @param token The token address of the reward
    function setRewardToken(
        address token,
        address router,
        address[] calldata path
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert NullAddress();
        LibDiamond.RewardToken storage rewardToken = _rs().rewardToken;

        rewardToken.token = token;
        rewardToken.router = router;
        rewardToken.path = path;

        _ds().swapRouters[router] = true;
        emit UpdateRewardToken(token);
    }

    function excludeFromReward(address _account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(LibDiamond.EXCLUDED_FROM_REWARD_ROLE, _account);
        _setBalance(_account, 0);
        _remove(_account);
    }

    function setMinBalanceForReward(uint256 newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _rs().minRewardBalance = newValue;
    }

    function setManualClaim(bool _manual) external {
        _rs().manualClaim[msg.sender] = _manual;
    }

    function updateClaimTimeout(uint32 _new)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_new < 3600 || _new > 86400) revert InvalidClaimTime();
        _rs().claimTimeout = _new;
    }

    // ==================== Internal ==================== //

    // This function uses a set amount of gas to process rewards for as many wallets as it can
    function _processRewards() internal {
        uint256 gas = _ds().processingGas;
        if (gas <= 0) return;

        uint256 numHolders = _rs().rewardHolders.keys.length;
        uint256 _lastProcessedIndex = _rs().lastProcessedIndex;
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 iterations = 0;

        while (gasUsed < gas && iterations < numHolders) {
            ++iterations;
            if (++_lastProcessedIndex >= _rs().rewardHolders.keys.length) {
                _lastProcessedIndex = 0;
            }
            address account = _rs().rewardHolders.keys[_lastProcessedIndex];

            if (_rs().manualClaim[account]) continue;

            if (!_canAutoClaim(_rs().claimTimes[account])) continue;
            _processAccount(account, false);

            uint256 newGasLeft = gasleft();
            if (gasLeft > newGasLeft) {
                gasUsed += gasLeft - newGasLeft;
            }
            gasLeft = newGasLeft;
        }
        _rs().lastProcessedIndex = _lastProcessedIndex;
    }

    /// @param newBalance The new balance to set for the account.
    function _setRewardBalance(address account, uint256 newBalance) internal {
        if (isExcludedFromRewards(account)) return;

        (, , , , , , uint256 amountTotal, uint256 released) = IVestingSchedule(
            _ds().vestingContract
        ).getVestingSchedule(account);
        if (amountTotal > 0) {
            newBalance += amountTotal - released;
        }

        if (newBalance >= _rs().minRewardBalance) {
            _setBalance(account, newBalance);
            _set(account, newBalance);
        } else {
            _setBalance(account, 0);
            _remove(account);
        }
    }

    function _swapETHAndWithdrawReward(
        address _owner,
        uint256 _value,
        bool _goHam
    ) internal returns (uint256) {
        LibDiamond.RewardToken memory rewardToken = _goHam
            ? _rs().goHam
            : _rs().rewardToken;

        try
            IUniswapV2Router02(rewardToken.router)
                .swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: _value
            }(
                0, // accept any amount of tokens
                rewardToken.path,
                address(_owner),
                block.timestamp
            )
        {
            emit RewardProcessed(_owner, _value, rewardToken.token);
            return _value;
        } catch {
            _rs().withdrawnReward[_owner] -= _value;
        }
        return 0;
    }

    function _canAutoClaim(uint256 lastClaimTime) internal view returns (bool) {
        return
            lastClaimTime > block.timestamp
                ? false
                : block.timestamp - lastClaimTime >= _rs().claimTimeout;
    }

    function _set(address key, uint256 val) internal {
        LibDiamond.Map storage rewardHolders = _rs().rewardHolders;
        if (rewardHolders.inserted[key]) {
            rewardHolders.values[key] = val;
        } else {
            rewardHolders.inserted[key] = true;
            rewardHolders.values[key] = val;
            rewardHolders.indexOf[key] = rewardHolders.keys.length;
            rewardHolders.keys.push(key);
        }
    }

    function _remove(address key) internal {
        LibDiamond.Map storage rewardHolders = _rs().rewardHolders;
        if (!rewardHolders.inserted[key]) {
            return;
        }

        delete rewardHolders.inserted[key];
        delete rewardHolders.values[key];

        uint256 index = rewardHolders.indexOf[key];
        uint256 lastIndex = rewardHolders.keys.length - 1;
        address lastKey = rewardHolders.keys[lastIndex];

        rewardHolders.indexOf[lastKey] = index;
        delete rewardHolders.indexOf[key];

        rewardHolders.keys[index] = lastKey;
        rewardHolders.keys.pop();
    }

    function getIndexOfKey(address key) internal view returns (int256 index) {
        return
            !_rs().rewardHolders.inserted[key]
                ? -1
                : int256(_rs().rewardHolders.indexOf[key]);
    }

    function _processAccount(address _owner, bool goHam) internal {
        uint256 _withdrawableReward = withdrawableDividendOf(_owner);
        if (_withdrawableReward <= 0) return;

        _rs().withdrawnReward[_owner] += _withdrawableReward;
        _rs().claimTimes[_owner] = block.timestamp;
        _swapETHAndWithdrawReward(_owner, _withdrawableReward, goHam);
    }

    function _setBalance(address _owner, uint256 _newBalance) internal {
        uint256 currentBalance = rewardBalanceOf(_owner);
        _rs().totalRewardSupply =
            _rs().totalRewardSupply +
            _newBalance -
            currentBalance;
        if (_newBalance > currentBalance) {
            _add(_owner, _newBalance - currentBalance);
        } else if (_newBalance < currentBalance) {
            _subtract(_owner, currentBalance - _newBalance);
        }
    }

    function _add(address _owner, uint256 value) internal {
        _rs().magnifiedReward[_owner] -= SafeCast.toInt256(
            _rs().magnifiedRewardPerShare * value
        );
        _rs().rewardBalances[_owner] += value;
    }

    function _subtract(address _owner, uint256 value) internal {
        _rs().magnifiedReward[_owner] += SafeCast.toInt256(
            _rs().magnifiedRewardPerShare * value
        );
        _rs().rewardBalances[_owner] -= value;
    }
}

