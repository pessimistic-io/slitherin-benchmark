// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./EnumerableSet.sol";

import "./IFactorScale.sol";

import "./VeHistoryLib.sol";

/**
 * @notice FactorScaleBase.sol is a modified version of Pendle's VotingControllerStorageUpg.sol:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/LiquidityMining
   /VotingController/VotingControllerStorageUpg.sol
 * 
 */
abstract contract FactorScaleBase is IFactorScale {
    using VeBalanceLib for VeBalance;
    using VeBalanceLib for LockedPosition;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Checkpoints for Checkpoints.History;
    using Helpers for uint128;

    // =============================================================
    //                          Errors
    // =============================================================

    error FSInvalidWTime(uint256 wTime);
    error FSInactiveVault(address vault);
    error FSZeroVeFctr(address user);
    error FSExceededMaxWeight(uint256 totalWeight, uint256 maxWeight);
    error FSEpochNotFinalized(uint256 wTime);
    error FSVaultAlreadyActive(address vault);
    error FSVaultAlreadyAddAndRemoved(address vault);
    error FSNotSetFctrPerSec();

    // GENERIC MSG
    error ArrayOutOfBounds();
    error ArrayLengthMismatch();

    struct VaultData {
        uint64 chainId;
        uint128 lastSlopeChangeAppliedAt;
        VeBalance totalVote;
        // wTime => slopeChange value
        mapping(uint128 => uint128) slopeChanges;
    }

    struct UserVaultData {
        uint64 weight;
        VeBalance vote;
    }

    struct UserData {
        uint64 totalVotedWeight;
        mapping(address => UserVaultData) voteForVaults;
    }

    struct WeekData {
        bool isEpochFinalized;
        uint128 totalVotes;
        mapping(address => uint128) vaultVotes;
    }

    struct FactorScaleStorage {
        address veFctr;
        uint128 deployedWTime;
        uint128 fctrPerSec;
        // [chainId] => [vault]
        mapping(uint64 => EnumerableSet.AddressSet) activeChainVaults;
        // [vaultAddress] -> VaultData
        mapping(address => VaultData) vaultData;
        // [wTime] => WeekData
        mapping(uint128 => WeekData) weekData;
        // user voting data
        mapping(address => UserData) userData;
        EnumerableSet.AddressSet allActiveVaults;
        EnumerableSet.AddressSet allRemovedVaults;
    }

    bytes32 private constant FACTOR_SCALE_STORAGE = keccak256('factor.scale.storage');

    function _getFactorScaleStorage() internal pure returns (FactorScaleStorage storage ds) {
        bytes32 slot = FACTOR_SCALE_STORAGE;
        assembly {
            ds.slot := slot
        }
    }

    uint128 public constant MAX_LOCK_TIME = 104 weeks;
    uint128 public constant WEEK = 1 weeks;
    uint128 public constant GOVERNANCE_FCTR_VOTE = 10 * (10 ** 6) * (10 ** 18); // 10 mils of FCTR

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function veFctr() external view returns (address) {
        return _getFactorScaleStorage().veFctr;
    }

    function deployedWTime() external view returns (uint128) {
        return _getFactorScaleStorage().deployedWTime;
    }

    function fctrPerSec() external view returns (uint128) {
        return _getFactorScaleStorage().fctrPerSec;
    }

    function getVaultTotalVoteAt(address vault, uint128 wTime) public view returns (uint128) {
        return _getFactorScaleStorage().weekData[wTime].vaultVotes[vault];
    }

    function getVaultData(
        address vault,
        uint128[] calldata wTimes
    )
        public
        view
        returns (
            uint64 chainId,
            uint128 lastSlopeChangeAppliedAt,
            VeBalance memory totalVote,
            uint128[] memory slopeChanges
        )
    {
        VaultData storage data = _getFactorScaleStorage().vaultData[vault];
        (chainId, lastSlopeChangeAppliedAt, totalVote) = (data.chainId, data.lastSlopeChangeAppliedAt, data.totalVote);

        slopeChanges = new uint128[](wTimes.length);
        for (uint256 i = 0; i < wTimes.length; ++i) {
            if (!wTimes[i].isValidWTime()) revert FSInvalidWTime(wTimes[i]);
            slopeChanges[i] = data.slopeChanges[wTimes[i]];
        }
    }

    function getUserData(
        address user,
        address[] calldata vaults
    ) public view returns (uint64 totalVotedWeight, UserVaultData[] memory voteForVaults) {
        UserData storage data = _getFactorScaleStorage().userData[user];

        totalVotedWeight = data.totalVotedWeight;

        voteForVaults = new UserVaultData[](vaults.length);
        for (uint256 i = 0; i < vaults.length; ++i) voteForVaults[i] = data.voteForVaults[vaults[i]];
    }

    function getWeekData(
        uint128 wTime,
        address[] calldata vaults
    ) public view returns (bool isEpochFinalized, uint128 totalVotes, uint128[] memory vaultVotes) {
        if (!wTime.isValidWTime()) revert FSInvalidWTime(wTime);

        WeekData storage data = _getFactorScaleStorage().weekData[wTime];

        (isEpochFinalized, totalVotes) = (data.isEpochFinalized, data.totalVotes);

        vaultVotes = new uint128[](vaults.length);
        for (uint256 i = 0; i < vaults.length; ++i) vaultVotes[i] = data.vaultVotes[vaults[i]];
    }

    function getAllActiveVaults() external view returns (address[] memory) {
        return _getFactorScaleStorage().allActiveVaults.values();
    }

    function getAllRemovedVaults(
        uint256 start,
        uint256 end
    ) external view returns (uint256 lengthOfRemovedVaults, address[] memory arr) {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        lengthOfRemovedVaults = $.allRemovedVaults.length();

        if (end >= lengthOfRemovedVaults) revert ArrayOutOfBounds();

        arr = new address[](end - start + 1);
        for (uint256 i = start; i <= end; ++i) arr[i - start] = $.allRemovedVaults.at(i);
    }

    function getActiveChainVaults(uint64 chainId) external view returns (address[] memory) {
        return _getFactorScaleStorage().activeChainVaults[chainId].values();
    }

    function getUserVaultVote(address user, address vault) external view returns (UserVaultData memory) {
        return _getFactorScaleStorage().userData[user].voteForVaults[vault];
    }

    /*///////////////////////////////////////////////////////////////
                INTERNAL DATA MANIPULATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addVault(uint64 chainId, address vault) internal {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        if (!$.activeChainVaults[chainId].add(vault)) assert(false);
        if (!$.allActiveVaults.add(vault)) assert(false);

        $.vaultData[vault].chainId = chainId;
        $.vaultData[vault].lastSlopeChangeAppliedAt = Helpers.getCurrentWeekStart();
    }

    function _removeVault(address vault) internal {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        uint64 chainId = $.vaultData[vault].chainId;
        if (!$.activeChainVaults[chainId].remove(vault)) assert(false);
        if (!$.allActiveVaults.remove(vault)) assert(false);
        if (!$.allRemovedVaults.add(vault)) assert(false);

        delete $.vaultData[vault];
    }

    function _setFinalVaultVoteForWeek(address vault, uint128 wTime, uint128 vote) internal {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        $.weekData[wTime].totalVotes += vote;
        $.weekData[wTime].vaultVotes[vault] = vote;
    }

    function _setNewVoteVaultData(address vault, VeBalance memory vote, uint128 wTime) internal {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        $.vaultData[vault].totalVote = vote;
        $.vaultData[vault].lastSlopeChangeAppliedAt = wTime;
        emit VaultVoteChange(vault, vote);
    }

    /**
     * @notice modifies `user`'s vote weight on `vault`
     * @dev works by simply removing the old vote position, then adds in a fresh vote
     */
    function _modifyVoteWeight(
        address user,
        address vault,
        LockedPosition memory userPosition,
        uint64 weight
    ) internal returns (VeBalance memory newVote) {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        UserData storage uData = $.userData[user];
        VaultData storage vData = $.vaultData[vault];

        VeBalance memory oldVote = uData.voteForVaults[vault].vote;

        // REMOVE OLD VOTE
        if (oldVote.bias != 0) {
            if (_isVaultActive(vault) && _isVoteActive(oldVote)) {
                vData.totalVote = vData.totalVote.sub(oldVote);
                vData.slopeChanges[oldVote.getExpiry()] -= oldVote.slope;
            }
            uData.totalVotedWeight -= uData.voteForVaults[vault].weight;
            delete uData.voteForVaults[vault];
        }

        // ADD NEW VOTE
        if (weight != 0) {
            if (!_isVaultActive(vault)) revert FSInactiveVault(vault);

            newVote = userPosition.convertToVeBalance(weight);

            vData.totalVote = vData.totalVote.add(newVote);
            vData.slopeChanges[newVote.getExpiry()] += newVote.slope;

            uData.voteForVaults[vault] = UserVaultData(weight, newVote);
            uData.totalVotedWeight += weight;
        }

        emit VaultVoteChange(vault, vData.totalVote);
    }

    function _setAllPastEpochsAsFinalized() internal {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        uint128 wTime = Helpers.getCurrentWeekStart();
        while (wTime > $.deployedWTime && $.weekData[wTime].isEpochFinalized == false) {
            $.weekData[wTime].isEpochFinalized = true;
            wTime -= WEEK;
        }
    }

    function _isVaultActive(address vault) internal view returns (bool) {
        return _getFactorScaleStorage().allActiveVaults.contains(vault);
    }

    /// @notice check if a vote still counts by checking if the vote is not (x,0) (in case the
    /// weight of the vote is too small) & the expiry is after the current time
    function _isVoteActive(VeBalance memory vote) internal view returns (bool) {
        return vote.slope != 0 && !Helpers.isCurrentlyExpired(vote.getExpiry());
    }
}

