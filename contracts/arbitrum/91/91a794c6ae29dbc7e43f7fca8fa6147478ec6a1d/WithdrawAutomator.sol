// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeOwnable } from "./SafeOwnable.sol";

import { Registry } from "./Registry.sol";
import { WithdrawAutomatorStorage } from "./WithdrawAutomatorStorage.sol";
import { VaultParent } from "./VaultParent.sol";
import { VaultParentInvestor } from "./VaultParentInvestor.sol";

import { Constants } from "./Constants.sol";

contract WithdrawAutomator is SafeOwnable {
    event SyncInitiated(address vault);
    event QueuedWithdraw(
        VaultParent vault,
        uint tokenId,
        uint shares,
        uint minUnitPrice,
        uint keeperFee,
        uint[] lzFees,
        uint totalLzFee,
        uint expiryTime,
        uint createdAtTime
    );
    event QueuedWithdrawExecuted(
        VaultParent vault,
        uint tokenId,
        uint shares,
        uint minUnitPrice,
        uint keeperFee,
        uint[] lzFees,
        uint totalLzFee,
        uint expiryTime,
        uint createdAtTime,
        uint refundedLzFees
    );

    function queueWithdrawAndSync(
        VaultParent vault,
        uint tokenId,
        uint shares,
        uint minUnitPrice,
        uint expiry,
        uint[] memory lzSyncFees
    ) external payable {
        uint totalSyncFees;

        for (uint i = 0; i < lzSyncFees.length; i++) {
            totalSyncFees += lzSyncFees[i];
        }
        vault.requestTotalValueUpdateMultiChain{ value: totalSyncFees }(
            lzSyncFees
        );
        emit SyncInitiated(address(vault));

        _queueWithdraw(
            vault,
            tokenId,
            shares,
            minUnitPrice,
            expiry,
            msg.value - totalSyncFees
        );
    }

    function queueWithdraw(
        VaultParent vault,
        uint tokenId,
        uint shares,
        uint minUnitPrice,
        uint expiry
    ) external payable {
        _queueWithdraw(vault, tokenId, shares, minUnitPrice, expiry, msg.value);
    }

    function executeWithdraw(address vault, uint index) external {
        WithdrawAutomatorStorage.QueuedWithdraw
            memory qWithdraw = _queuedWithdraw(vault, index);
        // Remove queued Withdraw
        _removeQueuedWithdraw(vault, index);
        // Remove the index for the vault -> tokenId mapping
        _removeQueuedWithdrawIndex(vault, qWithdraw.tokenId, index);

        require(block.timestamp <= qWithdraw.expiryTime, 'expired withdraw');
        (uint minCurrentUnitPrice, ) = qWithdraw.vault.unitPrice();

        require(
            minCurrentUnitPrice >= qWithdraw.minUnitPrice,
            'min unit price not met'
        );

        (uint[] memory lzFees, uint totalSendFee) = qWithdraw
            .vault
            .getLzFeesMultiChain(qWithdraw.vault.withdrawMultiChain.selector);

        require(qWithdraw.totalLzFee >= totalSendFee, 'insufficient lz fees');

        {
            uint holdingTotalShares = qWithdraw
                .vault
                .holdings(qWithdraw.tokenId)
                .totalShares;

            (uint streamingFees, uint performanceFees) = qWithdraw
                .vault
                .calculateUnpaidFees(qWithdraw.tokenId, minCurrentUnitPrice);

            uint holdingTotalSharesAfterFees = holdingTotalShares -
                streamingFees -
                performanceFees;

            if (qWithdraw.shares >= holdingTotalSharesAfterFees) {
                qWithdraw.shares = holdingTotalSharesAfterFees;
            }
        }

        qWithdraw.vault.withdrawMultiChain{ value: totalSendFee }(
            qWithdraw.tokenId,
            qWithdraw.shares,
            lzFees
        );

        // Pay Keeper
        (bool keeprSent, ) = msg.sender.call{ value: qWithdraw.keeperFee }('');
        require(keeprSent, 'Failed to pay keeper');
        // Refund and excess lzFees
        uint lzRefund;
        if (qWithdraw.totalLzFee > totalSendFee) {
            // Refund the difference
            lzRefund = qWithdraw.totalLzFee - totalSendFee;
        }

        if (lzRefund > 0) {
            (bool lzRefundSent, ) = qWithdraw
                .vault
                .ownerOf(qWithdraw.tokenId)
                .call{ value: lzRefund }('');
            require(lzRefundSent, 'Failed to refund');
        }

        WithdrawAutomatorStorage
        .layout()
        .executedWithdrawsByVaultByTokenId[vault][qWithdraw.tokenId].push(
                qWithdraw
            );

        emit QueuedWithdrawExecuted(
            qWithdraw.vault,
            qWithdraw.tokenId,
            qWithdraw.shares,
            qWithdraw.minUnitPrice,
            qWithdraw.keeperFee,
            lzFees,
            totalSendFee,
            qWithdraw.expiryTime,
            qWithdraw.createdAtTime,
            lzRefund
        );
    }

    // There is no incentive for anyone accepts the tokenOwner to call this function
    // Though if the queuedWithdraw has expired anyone can call this function
    // They wont receive any benefit though
    function removeQueuedWithdraw(address vault, uint index) external {
        WithdrawAutomatorStorage.QueuedWithdraw
            memory qWithdraw = _queuedWithdraw(vault, index);

        address tokenOwner = qWithdraw.vault.ownerOf(qWithdraw.tokenId);

        if (qWithdraw.expiryTime > block.timestamp) {
            require(tokenOwner == msg.sender, 'not owner');
        }

        // Remove queued Withdraw
        _removeQueuedWithdraw(vault, index);
        // Remove the index for the vault -> tokenId mapping
        _removeQueuedWithdrawIndex(vault, qWithdraw.tokenId, index);

        // Refund the tokenOwner the keeper fee and the lzFee
        (bool sent, ) = tokenOwner.call{
            value: qWithdraw.keeperFee + qWithdraw.totalLzFee
        }('');
        require(sent, 'Failed to refund');
    }

    function setKeeperFee(uint _keeperFee) external onlyOwner {
        WithdrawAutomatorStorage.layout().keeperFee = _keeperFee;
    }

    function setLzFeeBufferBasisPoints(
        uint _lzFeeBufferBasisPoints
    ) external onlyOwner {
        require(
            _lzFeeBufferBasisPoints <= Constants.BASIS_POINTS_DIVISOR,
            'invalid basis points'
        );
        WithdrawAutomatorStorage
            .layout()
            .lzFeeBufferBasisPoints = _lzFeeBufferBasisPoints;
    }

    function lzFeeBufferBasisPoints() external view returns (uint) {
        return WithdrawAutomatorStorage.layout().lzFeeBufferBasisPoints;
    }

    function keeperFee() external view returns (uint) {
        return WithdrawAutomatorStorage.layout().keeperFee;
    }

    function canExecute(
        address vault,
        uint index
    ) external view returns (bool, string memory) {
        WithdrawAutomatorStorage.QueuedWithdraw
            memory qWithdraw = _queuedWithdraw(address(vault), index);

        if (block.timestamp > qWithdraw.expiryTime) {
            return (false, 'expired');
        }

        if (qWithdraw.vault.holdingLocked(qWithdraw.tokenId)) {
            return (false, 'holding locked');
        }

        try qWithdraw.vault.unitPrice() returns (
            uint minCurrentUnitPrice,
            uint
        ) {
            if (minCurrentUnitPrice < qWithdraw.minUnitPrice) {
                return (false, 'price to low');
            }
        } catch {
            return (false, 'vault not synced');
        }

        (, uint totalSendFee) = qWithdraw.vault.getLzFeesMultiChain(
            qWithdraw.vault.withdrawMultiChain.selector
        );

        if (totalSendFee > qWithdraw.totalLzFee) {
            return (false, 'captured fees to low');
        }

        return (true, '');
    }

    function executedWithdrawsByVaultByTokenId(
        address vault,
        uint tokenId
    ) external view returns (WithdrawAutomatorStorage.QueuedWithdraw[] memory) {
        return
            WithdrawAutomatorStorage.layout().executedWithdrawsByVaultByTokenId[
                vault
            ][tokenId];
    }

    function getWithdrawLzFees(
        VaultParent vault
    ) external view returns (uint[] memory lzFees, uint256 totalSendFee) {
        return _getWithdrawLzFees(vault);
    }

    function getSyncLzFees(
        VaultParent vault
    ) external view returns (uint[] memory lzFees, uint256 totalSendFee) {
        return
            vault.getLzFeesMultiChain(
                vault.requestTotalValueUpdateMultiChain.selector
            );
    }

    function queuedWithdrawIndexesByVaultByTokenId(
        address vault,
        uint tokenId
    ) external view returns (uint[] memory) {
        return
            WithdrawAutomatorStorage
                .layout()
                .queuedWithdrawIndexesByVaultByTokenId[vault][tokenId];
    }

    function queuedWithdrawByVaultByIndex(
        address vault,
        uint index
    ) external view returns (WithdrawAutomatorStorage.QueuedWithdraw memory) {
        return _queuedWithdraw(vault, index);
    }

    function numberOfQueuedWithdrawsByVault(
        address vault
    ) external view returns (uint) {
        return
            WithdrawAutomatorStorage
                .layout()
                .queuedWithdrawsByVault[vault]
                .length;
    }

    function queuedWithdrawsByVault(
        address vault
    ) external view returns (WithdrawAutomatorStorage.QueuedWithdraw[] memory) {
        return WithdrawAutomatorStorage.layout().queuedWithdrawsByVault[vault];
    }

    function _queueWithdraw(
        VaultParent vault,
        uint tokenId,
        uint shares,
        uint minUnitPrice,
        uint expiry,
        uint feesPaid
    ) internal {
        require(vault.ownerOf(tokenId) == msg.sender, 'not owner');
        require(!vault.holdingLocked(tokenId), 'holding locked');
        // If no sync is required there is no point queueign a withdraw
        require(vault.requiresSyncForWithdraw(tokenId), 'no sync needed');
        require(expiry > block.timestamp + 10 minutes, 'expiry to short');

        WithdrawAutomatorStorage.Layout storage l = WithdrawAutomatorStorage
            .layout();

        (uint[] memory lzFees, uint totalSendFee) = _getWithdrawLzFees(vault);

        require(feesPaid >= l.keeperFee + totalSendFee, 'insufficient fee');

        WithdrawAutomatorStorage.QueuedWithdraw[] storage _queuedWithdraws = l
            .queuedWithdrawsByVault[address(vault)];
        _queuedWithdraws.push(
            WithdrawAutomatorStorage.QueuedWithdraw({
                vault: vault,
                tokenId: tokenId,
                shares: shares,
                minUnitPrice: minUnitPrice,
                keeperFee: l.keeperFee,
                lzFees: lzFees,
                totalLzFee: totalSendFee,
                expiryTime: expiry,
                createdAtTime: block.timestamp
            })
        );

        uint[] storage _queuedWithdrawIndexes = l
            .queuedWithdrawIndexesByVaultByTokenId[address(vault)][tokenId];
        _queuedWithdrawIndexes.push(_queuedWithdraws.length - 1);

        // Later we can support multiple queued withdraws per tokenId
        require(_queuedWithdrawIndexes.length == 1, '1 queue per holding');

        emit QueuedWithdraw(
            vault,
            tokenId,
            shares,
            minUnitPrice,
            l.keeperFee,
            lzFees,
            totalSendFee,
            expiry,
            block.timestamp
        );
    }

    function _removeQueuedWithdraw(address vault, uint index) internal {
        _removeFromArray(
            WithdrawAutomatorStorage.layout().queuedWithdrawsByVault[vault],
            index
        );
    }

    function _removeQueuedWithdrawIndex(
        address vault,
        uint tokenId,
        uint index
    ) internal {
        uint[] storage _queuedWithdrawIndexes = WithdrawAutomatorStorage
            .layout()
            .queuedWithdrawIndexesByVaultByTokenId[address(vault)][tokenId];

        for (uint i = 0; i < _queuedWithdrawIndexes.length; i++) {
            if (_queuedWithdrawIndexes[i] == index) {
                _removeFromArray(_queuedWithdrawIndexes, i);
                return;
            }
        }
    }

    function _removeFromArray(
        WithdrawAutomatorStorage.QueuedWithdraw[] storage array,
        uint index
    ) internal {
        require(index < array.length);
        array[index] = array[array.length - 1];
        array.pop();
    }

    function _removeFromArray(uint[] storage array, uint index) internal {
        require(index < array.length);
        array[index] = array[array.length - 1];
        array.pop();
    }

    function _queuedWithdraw(
        address vault,
        uint index
    ) internal view returns (WithdrawAutomatorStorage.QueuedWithdraw memory) {
        return
            WithdrawAutomatorStorage.layout().queuedWithdrawsByVault[vault][
                index
            ];
    }

    // The lzFees can change over time based on the cost of destination gas
    // Because this order will be queued at a later date, we need to add a buffer that accounts for this change
    // This is refunded to the caller.
    function _getWithdrawLzFees(
        VaultParent vault
    ) internal view returns (uint[] memory lzFees, uint256 totalSendFee) {
        WithdrawAutomatorStorage.Layout storage l = WithdrawAutomatorStorage
            .layout();
        (lzFees, ) = vault.getLzFeesMultiChain(
            vault.withdrawMultiChain.selector
        );
        for (uint i = 0; i < lzFees.length; i++) {
            lzFees[i] +=
                (lzFees[i] * l.lzFeeBufferBasisPoints) /
                Constants.BASIS_POINTS_DIVISOR;
            totalSendFee += lzFees[i];
        }
    }
}

