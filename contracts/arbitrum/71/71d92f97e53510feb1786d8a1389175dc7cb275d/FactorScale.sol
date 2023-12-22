// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IFactorGaugeControllerMainchain.sol";
import "./IVotingEscrow.sol";

import "./FactorScaleBase.sol";
import "./FactorMsgSenderUpgradeable.sol";

/**
 * @notice FactorScale.sol is a modified version of Pendle's VotingController:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts
   /LiquidityMining/VotingController/PendleVotingControllerUpg.sol
 * 
 *
 * @dev Voting accounting:
    - For gauge controller, it will consider each message from factor scale
    as a pack of money to incentivize it during the very next WEEK (block.timestamp -> block.timestamp + WEEK)
    - If the reward duration for the last pack of money has not ended, it will combine
    the leftover reward with the current reward to distribute.

    - In the very extreme case where no one broadcast the result of week x, and at week x+1,
    the results for both are now broadcasted, then the WEEK of (block.timestamp -> WEEK)
    will receive both of the reward pack
    - Each pack of money will has it own id as timestamp, a gauge controller does not
    receive a pack of money with the same id twice, this allow governance to rebroadcast
    in case the last message was corrupted by LayerZero

 Pros:
    - If governance does not forget broadcasting the reward on the early of the week,
    the mechanism works just the same as the epoch-based one
    - If governance forget to broadcast the reward, the whole system still works normally,
    the reward is still incentivized, but only approximately fair
 Cons:
    - Does not guarantee the reward will be distributed on epoch start and end
*/

contract FactorScale is FactorMsgSenderUpgradeable, FactorScaleBase {
    using VeBalanceLib for VeBalance;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _veFctr,
        address _fctrMsgSendEndpoint,
        uint256 initialApproxDestinationGas
    ) public initializer {
        __Ownable_init(msg.sender);
        __FactorMsgSender_init(_fctrMsgSendEndpoint, initialApproxDestinationGas);
        _getFactorScaleStorage().veFctr = _veFctr;
        _getFactorScaleStorage().deployedWTime = Helpers.getCurrentWeekStart();
    }

    /*///////////////////////////////////////////////////////////////
                FUNCTIONS CAN BE CALLED BY ANYONE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice updates a user's vote weights, also allowing user to divide their voting power
     * across different vaults
     * @param vaults vaults to change vote weights, if not listed then existing weight won't change
     * @param weights voting weight on each vault in `vaults`, must be same length as `vaults`
     * @dev A user's max voting weights is equal to `USER_VOTE_MAX_WEIGHT` (1e18). If their total
     * voted weights is less than such, then the excess weight is not counted. For such reason, a
     * user's voting power will only be fully utilized if their total voted weight is exactly 1e18.
     * @dev Reverts if, after all vote changes, the total voted weight is more than 1e18.
     * @dev A removed vault can be included, but the new weight must be 0, otherwise will revert.
     * @dev See {`FactorScaleBase - getUserData()`} for current user data.
     */
    function vote(address[] calldata vaults, uint64[] calldata weights) external {
        address user = msg.sender;

        FactorScaleStorage storage $ = _getFactorScaleStorage();

        if (vaults.length != weights.length) revert ArrayLengthMismatch();

        if (user != owner() && IVotingEscrow($.veFctr).balanceOf(user) == 0) 
            revert FSZeroVeFctr(user);

        LockedPosition memory userPosition = _getUserVeFctrPosition(user);

        for (uint256 i = 0; i < vaults.length; ++i) {
            if (_isVaultActive(vaults[i])) applyVaultSlopeChanges(vaults[i]);
            VeBalance memory newVote = _modifyVoteWeight(user, vaults[i], userPosition, weights[i]);
            emit Vote(user, vaults[i], weights[i], newVote);
        }

        uint256 totalVotedWeight = $.userData[user].totalVotedWeight;
        if (totalVotedWeight > VeBalanceLib.USER_VOTE_MAX_WEIGHT)
            revert FSExceededMaxWeight(totalVotedWeight, VeBalanceLib.USER_VOTE_MAX_WEIGHT);
    }

    /**
     * @notice Process all the slopeChanges that haven't been processed & update these data into
     * vaultData
     * @dev reverts if vault is not active
     * @dev if vault is already up-to-date, the function will succeed without any state updates
     */
    function applyVaultSlopeChanges(address vault) public {
        if (!_isVaultActive(vault)) revert FSInactiveVault(vault);

        FactorScaleStorage storage $ = _getFactorScaleStorage();

        uint128 wTime = $.vaultData[vault].lastSlopeChangeAppliedAt;
        uint128 currentWeekStart = Helpers.getCurrentWeekStart();

        // no state changes are expected
        if (wTime >= currentWeekStart) return;

        VeBalance memory currentVote = $.vaultData[vault].totalVote;
        while (wTime < currentWeekStart) {
            wTime += WEEK;
            currentVote = currentVote.sub($.vaultData[vault].slopeChanges[wTime], wTime);
            _setFinalVaultVoteForWeek(vault, wTime, currentVote.getValueAt(wTime));
        }

        _setNewVoteVaultData(vault, currentVote, wTime);
    }

    /**
     * @notice finalize the voting results of all vaults, up to the current epoch
     * @dev See `applyVaultSlopeChanges()` for more details
     * @dev This function might be gas-costly if there are a lot of active vaults, but this can be
     * mitigated by calling `applyVaultSlopeChanges()` for each vault separately, spreading the gas
     * cost across multiple txs (although the total gas cost will be higher).
     * This is because `applyVaultSlopeChanges()` will not update anything if already up-to-date.
     */
    function finalizeEpoch() public {
        uint256 length = _getFactorScaleStorage().allActiveVaults.length();
        for (uint256 i = 0; i < length; ++i) {
            applyVaultSlopeChanges(_getFactorScaleStorage().allActiveVaults.at(i));
        }
        _setAllPastEpochsAsFinalized();
    }

    /**
     * @notice broadcast the voting results of the current week to the chain with chainId. Can be
     * called by anyone.
     * @dev It's intentional to allow the same results to be broadcasted multiple
     * times. The receiver should be able to filter these duplicated messages
     * @dev The epoch must have already been finalized by `finalizeEpoch()`, otherwise will revert.
     */
    function broadcastResults(uint64 chainId) external payable refundUnusedEth {
        uint128 wTime = Helpers.getCurrentWeekStart();
        FactorScaleStorage storage $ = _getFactorScaleStorage();
        if (!$.weekData[wTime].isEpochFinalized) revert FSEpochNotFinalized(wTime);
        if ($.fctrPerSec == 0) revert FSNotSetFctrPerSec();
        _broadcastResults(chainId, wTime, $.fctrPerSec);
    }

    /*///////////////////////////////////////////////////////////////
                    GOVERNANCE-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice add a vault to allow users to vote. Can only be done by governance
     * @custom:gov NOTE TO GOV:
     * - Previous week's results should have been broadcasted prior to calling this function.
     * - `vault` must not have been added before (even if has been removed).
     * - `chainId` must be valid.
     */
    function addVault(uint64 chainId, address vault) external onlyOwner {
        if (_isVaultActive(vault)) revert FSVaultAlreadyActive(vault);

        if (_getFactorScaleStorage().allRemovedVaults.contains(vault)) 
            revert FSVaultAlreadyAddAndRemoved(vault);

        _addVault(chainId, vault);

        emit AddVault(chainId, vault);
    }

    /**
     * @notice remove a vault from voting. Can only be done by governance
     * @custom:gov NOTE TO GOV:
     * - Previous week's results should have been broadcasted prior to calling this function.
     * - `vault` must be currently active.
     */
    function removeVault(address vault) external onlyOwner {
        if (!_isVaultActive(vault)) revert FSInactiveVault(vault);

        uint64 chainId = _getFactorScaleStorage().vaultData[vault].chainId;

        applyVaultSlopeChanges(vault);

        _removeVault(vault);

        emit RemoveVault(chainId, vault);
    }

    /**
     * @notice use the gov-privilege to force broadcast a message in case there are issues with LayerZero
     * @custom:gov NOTE TO GOV: gov should always call finalizeEpoch beforehand
     */
    function forceBroadcastResults(
        uint64 chainId,
        uint128 wTime,
        uint128 forcedFctrPerSec
    ) external payable onlyOwner refundUnusedEth {
        _broadcastResults(chainId, wTime, forcedFctrPerSec);
    }

    /**
     * @notice sets new fctrPerSec
     * @dev no zero checks because gov may want to stop liquidity mining
     * @custom:gov NOTE TO GOV: Should be done mid-week, well before the next broadcast to avoid
     * race condition
     */
    function setFctrPerSec(uint128 newFctrPerSec) external onlyOwner {
        _getFactorScaleStorage().fctrPerSec = newFctrPerSec;
        emit SetFctrPerSec(newFctrPerSec);
    }

    function getBroadcastResultFee(uint64 chainId) external view returns (uint256) {
        if (chainId == block.chainid) return 0; // Mainchain broadcast

        uint256 length = _getFactorScaleStorage().activeChainVaults[chainId].length();
        if (length == 0) return 0;

        address[] memory vaults = new address[](length);
        uint256[] memory totalFctrAmounts = new uint256[](length);

        return _getSendMessageFee(
            chainId, abi.encode(uint128(0), vaults, totalFctrAmounts)
        );
    }

    function isVaultActive(address vault) external view returns (bool) {
        return _isVaultActive(vault);
    }

    /*///////////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice broadcast voting results of the timestamp to chainId
    function _broadcastResults(uint64 chainId, uint128 wTime, uint128 totalFctrPerSec) internal {
        FactorScaleStorage storage $ = _getFactorScaleStorage();

        uint256 totalVotes = $.weekData[wTime].totalVotes;
        if (totalVotes == 0) return;

        uint256 length = $.activeChainVaults[chainId].length();
        if (length == 0) return;

        address[] memory vaults = $.activeChainVaults[chainId].values();
        uint256[] memory totalFctrAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            uint256 vaultVotes = $.weekData[wTime].vaultVotes[vaults[i]];
            totalFctrAmounts[i] = (totalFctrPerSec * vaultVotes * WEEK) / totalVotes;
        }

        if (chainId == block.chainid) {
            address gaugeController = _getMsgSenderStorage().destinationContracts.get(chainId);
            IFactorGaugeControllerMainchain(gaugeController).updateVotingResults(
                wTime,
                vaults,
                totalFctrAmounts
            );
        } else {
            _sendMessage(chainId, abi.encode(wTime, vaults, totalFctrAmounts));
        }

        emit BroadcastResults(chainId, wTime, totalFctrPerSec);
    }

    function _getUserVeFctrPosition(
        address user
    ) internal view returns (LockedPosition memory userPosition) {
        if (user == owner()) {
            (userPosition.amount, userPosition.expiry) = (
                GOVERNANCE_FCTR_VOTE,
                Helpers.getWeekStartTimestamp(uint128(block.timestamp) + MAX_LOCK_TIME)
            );
        } else {
            (userPosition.amount, userPosition.expiry) = 
                IVotingEscrow(_getFactorScaleStorage().veFctr).positionData(user);
        }
    }
}

