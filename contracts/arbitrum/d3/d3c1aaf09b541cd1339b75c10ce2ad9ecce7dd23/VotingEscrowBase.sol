// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./IVotingEscrow.sol";

import "./Helpers.sol";
import "./VeBalanceLib.sol";

/**
 * @notice This contract is a modified version of Pendle's VotingEscrowTokenBase.sol:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/LiquidityMining
 * /VotingEscrow/VotingEscrowTokenBase.sol
 *
 * @dev This contract is an abstract for its mainchain and sidechain variant
 * PRINCIPLE:
 *   - All functions implemented in this contract should be either view or pure
 *     to ensure that no writing logic is inherited by sidechain version
 *   - Mainchain version will handle the logic which are:
 *        + Deposit, withdraw, increase lock, increase amount
 *        + Mainchain logic will be ensured to have _totalSupply = linear sum of
 *          all users' veBalance such that their locks are not yet expired
 *        + Mainchain contract reserves 100% the right to write on sidechain
 *        + No other transaction is allowed to write on sidechain storage
 */

abstract contract VotingEscrowBase is IVotingEscrow {
    using VeBalanceLib for VeBalance;
    using VeBalanceLib for LockedPosition;

    struct VEBaseStorage {
        VeBalance _totalSupply;
        mapping(address => LockedPosition) positionData;
    }

    bytes32 private constant VE_BASE_STORAGE = keccak256('factor.votingescrow.BaseStorage');

    function _getVEBaseStorage() internal pure returns (VEBaseStorage storage ds) {
        bytes32 slot = VE_BASE_STORAGE;
        assembly {
            ds.slot := slot
        }
    }

    uint128 public constant MAX_LOCK_TIME = 104 weeks;
    uint128 public constant MIN_LOCK_TIME = 1 weeks;

    function balanceOf(address user) public view virtual returns (uint128) {
        return _getVEBaseStorage().positionData[user].convertToVeBalance().getCurrentValue();
    }

    function balanceOfAt(address user, uint128 timestamp) public view virtual returns (uint128) {
        return _getVEBaseStorage().positionData[user].convertToVeBalance().getValueAt(timestamp);
    }

    function totalSupplyStored() public view virtual returns (uint128) {
        return _getVEBaseStorage()._totalSupply.getCurrentValue();
    }

    function totalSupplyCurrent() public virtual returns (uint128);

    function _isPositionExpired(address user) internal view returns (bool) {
        return Helpers.isCurrentlyExpired(_getVEBaseStorage().positionData[user].expiry);
    }

    function totalSupplyAndBalanceCurrent(address user) external returns (uint128, uint128) {
        return (totalSupplyCurrent(), balanceOf(user));
    }

    function positionData(address user) public view returns (uint128 amount, uint128 expiry) {
        VEBaseStorage storage $ = _getVEBaseStorage();
        amount = $.positionData[user].amount;
        expiry = $.positionData[user].expiry;
    }
}

