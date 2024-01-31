// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Math.sol";
import "./IERC20Entity.sol";

struct ExtractorInfo {
    uint128 shares;
    int128 rewardDebt;
}

struct MineInfo {
    uint128 rewardPerShare;
    uint64 lastRewardTimestamp;
    uint64 rewardPerSecond;
    uint128 totalShares;
    uint128 totalReward;
}

/// @title Mining System
/// @author boffee
/// @author Modified fro MasterChef V2 (https://github.com/sushiswap/sushiswap/blob/master/protocols/masterchef/contracts/MasterChefV2.sol)
/// @notice This contract is used to manage mining.
contract MiningSystem {
    event Dock(
        uint256 indexed extractorId,
        uint256 indexed mineId,
        uint256 shares
    );
    event Undock(
        uint256 indexed extractorId,
        uint256 indexed mineId,
        uint256 shares
    );
    event EmergencyUndock(
        uint256 indexed extractorId,
        uint256 indexed mineId,
        uint256 shares
    );
    event Extract(
        uint256 indexed extractorId,
        uint256 indexed mineId,
        uint256 reward
    );
    event AddMine(
        uint256 indexed mineId,
        address indexed rewardToken,
        uint256 rewardPerSecond,
        uint256 rewardPool
    );
    event SetMine(
        uint256 indexed mineId,
        address indexed rewardToken,
        uint256 rewardPerSecond,
        uint256 rewardPool
    );
    event UpdateMine(
        uint256 indexed mineId,
        uint64 lastRewardTimestamp,
        uint256 totalShares,
        uint256 rewardPerShare
    );
    event DestroyMine(uint256 indexed mineId);

    uint256 public constant REWARD_PER_SHARE_PRECISION = 1e12;

    /// @notice Info of each mine.
    mapping(uint256 => MineInfo) private _mineInfos;

    /// @notice Info of each extractor at each mine.
    mapping(uint256 => mapping(uint256 => ExtractorInfo))
        private _extractorInfos;

    /// @notice Mine reward token address.
    mapping(uint256 => IERC20Entity) public rewardTokens;

    function exists(uint256 mineId) public view returns (bool) {
        return address(rewardTokens[mineId]) != address(0);
    }

    /// @notice View function to see pending reward on frontend.
    /// @param extractorId Address of extractor.
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @return pending reward for a given extractor.
    function pendingReward(uint256 extractorId, uint256 mineId)
        external
        view
        returns (uint256 pending)
    {
        MineInfo memory mineInfo = _mineInfos[mineId];
        ExtractorInfo storage extractorInfo = _extractorInfos[mineId][
            extractorId
        ];
        uint256 rewardPerShare = mineInfo.rewardPerShare;
        if (
            block.timestamp > mineInfo.lastRewardTimestamp &&
            mineInfo.totalShares != 0
        ) {
            uint256 duration = block.timestamp - mineInfo.lastRewardTimestamp;
            uint256 reward = Math.min(
                duration * mineInfo.rewardPerSecond,
                rewardTokens[mineId].balanceOf(mineId) - mineInfo.totalReward
            );
            // total reward cannot excceed mine balance
            rewardPerShare +=
                (reward * REWARD_PER_SHARE_PRECISION) /
                mineInfo.totalShares;
        }
        pending = uint256(
            int256(
                (extractorInfo.shares * rewardPerShare) /
                    REWARD_PER_SHARE_PRECISION
            ) - extractorInfo.rewardDebt
        );
    }

    /// @notice get mine info
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @return mineInfo
    function getMineInfo(uint256 mineId) public view returns (MineInfo memory) {
        return _mineInfos[mineId];
    }

    /// @notice get extractor info
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @param extractorId id of the extractor. See `_extractorInfos`.
    /// @return extractorInfo
    function getExtractorInfo(uint256 mineId, uint256 extractorId)
        public
        view
        returns (ExtractorInfo memory)
    {
        return _extractorInfos[mineId][extractorId];
    }

    /// @notice Update reward variables for all mines.
    /// @param mineIds Mine IDs of all to be updated.
    function massUpdateMines(uint256[] calldata mineIds) external {
        uint256 len = mineIds.length;
        for (uint256 i = 0; i < len; ++i) {
            updateMine(mineIds[i]);
        }
    }

    /// @notice Update reward variables of the given mine.
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @return mineInfo Returns the mine that was updated.
    function updateMine(uint256 mineId)
        public
        returns (MineInfo memory mineInfo)
    {
        mineInfo = _mineInfos[mineId];
        if (block.timestamp > mineInfo.lastRewardTimestamp) {
            if (mineInfo.totalShares > 0) {
                uint256 duration = block.timestamp -
                    mineInfo.lastRewardTimestamp;
                uint256 reward = Math.min(
                    duration * mineInfo.rewardPerSecond,
                    rewardTokens[mineId].balanceOf(mineId) -
                        mineInfo.totalReward
                );
                mineInfo.totalReward += uint128(reward);
                // total reward cannot excceed mine balance
                mineInfo.rewardPerShare += uint128(
                    (reward * REWARD_PER_SHARE_PRECISION) / mineInfo.totalShares
                );
            }
            mineInfo.lastRewardTimestamp = uint64(block.timestamp);
            _mineInfos[mineId] = mineInfo;
            emit UpdateMine(
                mineId,
                mineInfo.lastRewardTimestamp,
                mineInfo.totalShares,
                mineInfo.rewardPerShare
            );
        }
    }

    /// @notice Dock extractor to mine for BUTTER allocation.
    /// @param extractorId The receiver of `shares` dock benefit.
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @param shares The amount of shares to be docked.
    function _dock(
        uint256 extractorId,
        uint256 mineId,
        uint256 shares
    ) internal {
        MineInfo memory mineInfo = updateMine(mineId);

        require(
            (mineInfo.totalShares * uint256(mineInfo.rewardPerShare)) /
                REWARD_PER_SHARE_PRECISION <
                rewardTokens[mineId].balanceOf(mineId),
            "Mine depleted"
        );

        ExtractorInfo storage extractorInfo = _extractorInfos[mineId][
            extractorId
        ];

        // Effects
        extractorInfo.shares += uint128(shares);
        extractorInfo.rewardDebt += int128(
            uint128(
                (shares * mineInfo.rewardPerShare) / REWARD_PER_SHARE_PRECISION
            )
        );
        _mineInfos[mineId].totalShares += uint128(shares);

        emit Dock(extractorId, mineId, shares);
    }

    /// @notice Undock extractor from mine.
    /// @param extractorId Receiver of the reward.
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @param shares Extractor shares to undock.
    function _undock(
        uint256 extractorId,
        uint256 mineId,
        uint256 shares
    ) internal {
        MineInfo memory mineInfo = updateMine(mineId);
        ExtractorInfo storage extractorInfo = _extractorInfos[mineId][
            extractorId
        ];

        // Effects
        extractorInfo.rewardDebt -= int128(
            uint128(
                (shares * mineInfo.rewardPerShare) / REWARD_PER_SHARE_PRECISION
            )
        );
        extractorInfo.shares -= uint128(shares);
        _mineInfos[mineId].totalShares -= uint128(shares);

        _tryDestroy(mineId);

        emit Undock(extractorId, mineId, shares);
    }

    /// @notice Extract proceeds for extractor.
    /// @param extractorId Receiver of rewards.
    /// @param mineId id of the mine. See `_mineInfos`.
    function _extract(uint256 extractorId, uint256 mineId) internal {
        MineInfo memory mineInfo = updateMine(mineId);
        ExtractorInfo storage extractorInfo = _extractorInfos[mineId][
            extractorId
        ];
        int256 accumulatedReward = int256(
            (extractorInfo.shares * uint256(mineInfo.rewardPerShare)) /
                REWARD_PER_SHARE_PRECISION
        );
        uint256 _pendingReward = uint256(
            accumulatedReward - extractorInfo.rewardDebt
        );

        // Effects
        extractorInfo.rewardDebt = int128(accumulatedReward);
        _mineInfos[mineId].totalReward -= uint128(_pendingReward);

        rewardTokens[mineId].transferFrom(mineId, extractorId, _pendingReward);

        _tryDestroy(mineId);

        emit Extract(extractorId, mineId, _pendingReward);
    }

    /// @notice Undock extractor from mine and extract proceeds.
    /// @param extractorId Receiver of the rewards.
    /// @param mineId id of the mine. See `_mineInfos`.
    /// @param shares Extractor shares to undock.
    function _undockAndExtract(
        uint256 extractorId,
        uint256 mineId,
        uint256 shares
    ) internal {
        MineInfo memory mineInfo = updateMine(mineId);
        ExtractorInfo storage extractorInfo = _extractorInfos[mineId][
            extractorId
        ];
        int256 accumulatedReward = int256(
            (extractorInfo.shares * uint256(mineInfo.rewardPerShare)) /
                REWARD_PER_SHARE_PRECISION
        );
        uint256 _pendingReward = uint256(
            accumulatedReward - extractorInfo.rewardDebt
        );

        // Effects
        extractorInfo.rewardDebt = int128(
            accumulatedReward -
                int256(
                    (shares * mineInfo.rewardPerShare) /
                        REWARD_PER_SHARE_PRECISION
                )
        );
        extractorInfo.shares -= uint128(shares);
        _mineInfos[mineId].totalShares -= uint128(shares);
        _mineInfos[mineId].totalReward -= uint128(_pendingReward);

        rewardTokens[mineId].transferFrom(mineId, extractorId, _pendingReward);

        _tryDestroy(mineId);

        emit Undock(extractorId, mineId, shares);
        emit Extract(extractorId, mineId, _pendingReward);
    }

    /// @notice Undock without caring about rewards. EMERGENCY ONLY.
    /// @param extractorId Receiver of the reward.
    /// @param mineId id of the mine. See `_mineInfos`.
    function _emergencyUndock(uint256 extractorId, uint256 mineId) internal {
        ExtractorInfo storage extractorInfo = _extractorInfos[mineId][
            extractorId
        ];
        uint256 shares = extractorInfo.shares;
        if (_mineInfos[mineId].totalShares >= shares) {
            _mineInfos[mineId].totalShares -= uint128(shares);
        }

        delete _extractorInfos[mineId][extractorId];

        emit EmergencyUndock(extractorId, mineId, shares);
    }

    /// @notice Add a new mine.
    /// @param mineId The id of the mine.
    /// @param rewardToken The address of the reward token.
    /// @param rewardPerSecond reward rate of the new mine.
    function _add(
        uint256 mineId,
        address rewardToken,
        uint256 rewardPerSecond
    ) internal {
        require(
            _mineInfos[mineId].lastRewardTimestamp == 0,
            "Mine already exists"
        );

        _mineInfos[mineId] = MineInfo({
            rewardPerSecond: uint64(rewardPerSecond),
            lastRewardTimestamp: uint64(block.timestamp),
            rewardPerShare: 0,
            totalShares: 0,
            totalReward: 0
        });
        rewardTokens[mineId] = IERC20Entity(rewardToken);

        emit AddMine(
            mineId,
            rewardToken,
            rewardPerSecond,
            IERC20Entity(rewardToken).balanceOf(mineId)
        );
    }

    /// @notice Update the given mine's reward rate.
    /// @param mineId The entity id of the mine.
    /// @param rewardPerSecond New reward rate of the mine.
    function _set(uint256 mineId, uint256 rewardPerSecond) internal {
        _mineInfos[mineId].rewardPerSecond = uint64(rewardPerSecond);
        IERC20Entity rewardToken = rewardTokens[mineId];

        emit SetMine(
            mineId,
            address(rewardToken),
            rewardPerSecond,
            rewardToken.balanceOf(mineId)
        );
    }

    /// @notice Destroy the given mine if its depleted and has no shares.
    /// @param mineId The entity id of the mine.
    function _tryDestroy(uint256 mineId) internal {
        if (
            rewardTokens[mineId].balanceOf(mineId) < 1e15 &&
            _mineInfos[mineId].totalShares < 1e15
        ) {
            _destroy(mineId);
        }
    }

    /// @notice Destroy the given mine.
    /// @param mineId The entity id of the mine.
    function _destroy(uint256 mineId) internal {
        delete _mineInfos[mineId];
        delete rewardTokens[mineId];
        emit DestroyMine(mineId);
    }

    function _destroyExtractor(uint256 mineId, uint256 extractorId) internal {
        ExtractorInfo memory extractorInfo = _extractorInfos[mineId][
            extractorId
        ];
        _mineInfos[mineId].totalShares -= uint128(extractorInfo.shares);
        _mineInfos[mineId].totalReward -= uint128(
            uint256(
                int256(
                    (extractorInfo.shares *
                        uint256(_mineInfos[mineId].rewardPerShare)) /
                        REWARD_PER_SHARE_PRECISION
                ) - extractorInfo.rewardDebt
            )
        );
        delete _extractorInfos[mineId][extractorId];
    }
}

