// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeOwnable } from "./SafeOwnable.sol";

import { Registry } from "./Registry.sol";
import { DepositAutomatorStorage } from "./DepositAutomatorStorage.sol";
import { VaultParent } from "./VaultParent.sol";
import { VaultParentInvestor } from "./VaultParentInvestor.sol";

import { Constants } from "./Constants.sol";

contract DepositAutomator is SafeOwnable {
    event DepositSyncInitiated(address vault);
    event QueuedDeposit(DepositAutomatorStorage.QueuedDeposit queuedDeposit);
    event QueuedDepositExecuted(
        DepositAutomatorStorage.QueuedDeposit queuedDeposit
    );

    function queueDepositAndSync(
        VaultParent vault,
        uint tokenId,
        IERC20 depositAsset,
        uint depositAmount,
        uint maxUnitPrice,
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
        emit DepositSyncInitiated(address(vault));

        _queueDeposit(
            vault,
            msg.sender,
            tokenId,
            depositAsset,
            depositAmount,
            maxUnitPrice,
            expiry,
            msg.value - totalSyncFees
        );
    }

    function queueDeposit(
        VaultParent vault,
        uint tokenId,
        IERC20 depositAsset,
        uint depositAmount,
        uint maxUnitPrice,
        uint expiry
    ) external payable {
        _queueDeposit(
            vault,
            msg.sender,
            tokenId,
            depositAsset,
            depositAmount,
            maxUnitPrice,
            expiry,
            msg.value
        );
    }

    function executeDeposit(address vault, uint index) external {
        DepositAutomatorStorage.QueuedDeposit memory qDeposit = _queuedDeposit(
            vault,
            index
        );
        require(block.timestamp <= qDeposit.expiryTime, 'expired Deposit');

        // Remove queued Deposit
        _removeQueuedDeposit(vault, qDeposit.depositor, index);

        (, uint maxCurrentUnitPrice) = qDeposit.vault.unitPrice();

        require(
            maxCurrentUnitPrice <= qDeposit.maxUnitPrice,
            'entry price too high'
        );

        qDeposit.depositAsset.transferFrom(
            qDeposit.depositor,
            address(this),
            qDeposit.depositAmount
        );

        qDeposit.depositAsset.approve(
            address(qDeposit.vault),
            qDeposit.depositAmount
        );

        qDeposit.vault.depositFor(
            qDeposit.depositor,
            qDeposit.tokenId,
            address(qDeposit.depositAsset),
            qDeposit.depositAmount
        );

        // Pay Keeper
        (bool keeprSent, ) = msg.sender.call{ value: qDeposit.keeperFee }('');
        require(keeprSent, 'Failed to pay keeper');

        DepositAutomatorStorage
        .layout()
        .executedDepositsByVaultByDepositor[vault][qDeposit.depositor].push(
                qDeposit
            );

        emit QueuedDepositExecuted(qDeposit);
    }

    // There is no incentive for anyone except the depositor to call this function
    // As the keeper fee is refunded to the original depositor
    // Though if the queuedDeposit has expired anyone can call this function
    // They wont receive any benefit though
    function removeQueuedDeposit(address vault, uint index) external {
        DepositAutomatorStorage.QueuedDeposit memory qDeposit = _queuedDeposit(
            vault,
            index
        );

        if (qDeposit.expiryTime > block.timestamp) {
            require(qDeposit.depositor == msg.sender, 'not owner');
        }

        _removeQueuedDeposit(vault, qDeposit.depositor, index);

        // Refund the tokenOwner the keeper fee
        (bool sent, ) = qDeposit.depositor.call{ value: qDeposit.keeperFee }(
            ''
        );
        require(sent, 'Failed to refund');
    }

    function setKeeperFee(uint _keeperFee) external onlyOwner {
        DepositAutomatorStorage.layout().keeperFee = _keeperFee;
    }

    function keeperFee() external view returns (uint) {
        return DepositAutomatorStorage.layout().keeperFee;
    }

    function canExecute(
        address vault,
        uint index
    ) external view returns (bool, string memory) {
        DepositAutomatorStorage.QueuedDeposit memory qDeposit = _queuedDeposit(
            address(vault),
            index
        );

        if (block.timestamp > qDeposit.expiryTime) {
            return (false, 'expired');
        }

        if (
            qDeposit.depositAsset.allowance(qDeposit.depositor, address(this)) <
            qDeposit.depositAmount
        ) {
            return (false, 'insufficient allowance');
        }

        if (
            qDeposit.depositAsset.balanceOf(qDeposit.depositor) <
            qDeposit.depositAmount
        ) {
            return (false, 'insufficient balance');
        }

        try qDeposit.vault.unitPrice() returns (
            uint,
            uint maxCurrentUnitPrice
        ) {
            if (maxCurrentUnitPrice > qDeposit.maxUnitPrice) {
                return (false, 'price to high');
            }
        } catch {
            return (false, 'vault not synced');
        }

        return (true, '');
    }

    function executedDepositsByVaultByDepositor(
        address vault,
        address depositor
    ) external view returns (DepositAutomatorStorage.QueuedDeposit[] memory) {
        return
            DepositAutomatorStorage.layout().executedDepositsByVaultByDepositor[
                vault
            ][depositor];
    }

    function getSyncLzFees(
        VaultParent vault
    ) external view returns (uint[] memory lzFees, uint256 totalSendFee) {
        return
            vault.getLzFeesMultiChain(
                vault.requestTotalValueUpdateMultiChain.selector
            );
    }

    function queuedDepositIndexesByVaultByDepositor(
        address vault,
        address depositor
    ) external view returns (uint[] memory) {
        return
            DepositAutomatorStorage
                .layout()
                .queuedDepositIndexesByVaultByDepositor[vault][depositor];
    }

    function queuedDepositByVaultByIndex(
        address vault,
        uint index
    ) external view returns (DepositAutomatorStorage.QueuedDeposit memory) {
        return _queuedDeposit(vault, index);
    }

    function numberOfQueuedDepositsByVault(
        address vault
    ) external view returns (uint) {
        return
            DepositAutomatorStorage
                .layout()
                .queuedDepositsByVault[vault]
                .length;
    }

    function queuedDepositsByVault(
        address vault
    ) external view returns (DepositAutomatorStorage.QueuedDeposit[] memory) {
        return DepositAutomatorStorage.layout().queuedDepositsByVault[vault];
    }

    function _queueDeposit(
        VaultParent vault,
        address depositor,
        uint tokenId,
        IERC20 depositAsset,
        uint depositAmount,
        uint maxUnitPrice,
        uint expiry,
        uint feesPaid
    ) internal {
        require(depositAmount > 0, 'deposit amount 0');
        // Don't use queueDeposit if the vault does not require sync. Deposit Directly.
        require(vault.requiresSyncForDeposit(), 'no sync needed');
        // At the moment we only allow one holding per depositor
        // We add this safety check here so that it doesn't fail when depositing
        if (tokenId == 0) {
            require(vault.balanceOf(depositor) == 0, 'already owns holding');
        } else {
            // Safety check to make sure users don't deposit into someone elses holding
            require(vault.ownerOf(tokenId) == depositor, 'not owner');
        }

        // The expiry has to be at least 10 minutes so that the sync has time to complete
        require(expiry > block.timestamp + 10 minutes, 'expiry to short');

        // Note: this contract only takes the funds when the deposit is executed.
        // The funds are transient and never held in this contract
        require(
            depositAsset.allowance(depositor, address(this)) >= depositAmount,
            'insufficient allowance'
        );

        require(
            depositAsset.balanceOf(depositor) >= depositAmount,
            'insufficient balance'
        );

        DepositAutomatorStorage.Layout storage l = DepositAutomatorStorage
            .layout();

        require(feesPaid >= l.keeperFee, 'insufficient fee');

        DepositAutomatorStorage.QueuedDeposit[] storage _queuedDeposits = l
            .queuedDepositsByVault[address(vault)];

        uint[] storage _queuedDepositIndexes = l
            .queuedDepositIndexesByVaultByDepositor[address(vault)][depositor];

        _cleanQueuedDepositIndexes(
            _queuedDepositIndexes,
            _queuedDeposits,
            depositor
        );

        // Later we can support multiple queued Deposits per depositor
        require(_queuedDepositIndexes.length == 0, '1 queue per depositor');

        DepositAutomatorStorage.QueuedDeposit
            memory qDeposit = DepositAutomatorStorage.QueuedDeposit({
                vault: vault,
                depositor: depositor,
                tokenId: tokenId,
                depositAsset: depositAsset,
                depositAmount: depositAmount,
                maxUnitPrice: maxUnitPrice,
                keeperFee: l.keeperFee,
                expiryTime: expiry,
                createdAtTime: block.timestamp,
                nonce: l.nonce++
            });

        _queuedDepositIndexes.push(_queuedDeposits.length);
        _queuedDeposits.push(qDeposit);

        emit QueuedDeposit(qDeposit);
    }

    function _cleanQueuedDepositIndexes(
        uint[] storage indexes,
        DepositAutomatorStorage.QueuedDeposit[] storage queuedDeposits,
        address depositor
    ) internal {
        for (uint i = 0; i < indexes.length; i++) {
            if (
                indexes[i] > queuedDeposits.length - 1 ||
                queuedDeposits[indexes[i]].depositor != depositor
            ) {
                _removeFromArray(indexes, i);
            }
        }
    }

    function _removeQueuedDeposit(
        address vault,
        address depositor,
        uint index
    ) internal {
        DepositAutomatorStorage.Layout storage l = DepositAutomatorStorage
            .layout();

        DepositAutomatorStorage.QueuedDeposit[] storage queuedDeposits = l
            .queuedDepositsByVault[vault];
        // The last element is moved to the index being removed
        uint lastIndex = queuedDeposits.length - 1;
        // Remove queued Deposit
        _removeFromArray(
            DepositAutomatorStorage.layout().queuedDepositsByVault[vault],
            index
        );

        // The mapping for the vault -> tokenId -> index needs to be updated
        _updateMovedDepositorIndex(queuedDeposits, vault, lastIndex, index);

        // Remove the index for the vault -> depositor mapping
        uint[] storage _queuedDepositIndexes = l
            .queuedDepositIndexesByVaultByDepositor[address(vault)][depositor];

        for (uint i = 0; i < _queuedDepositIndexes.length; i++) {
            if (_queuedDepositIndexes[i] == index) {
                _removeFromArray(_queuedDepositIndexes, i);
                return;
            }
        }
    }

    function _updateMovedDepositorIndex(
        DepositAutomatorStorage.QueuedDeposit[] storage queuedDeposits,
        address vault,
        uint oldIndex,
        uint newIndex
    ) internal {
        if (newIndex < queuedDeposits.length) {
            DepositAutomatorStorage.QueuedDeposit
                memory atIndex = queuedDeposits[newIndex];

            uint[]
                storage queuedDepositIndexesForDepositor = DepositAutomatorStorage
                    .layout()
                    .queuedDepositIndexesByVaultByDepositor[address(vault)][
                        atIndex.depositor
                    ];
            for (uint i = 0; i < queuedDepositIndexesForDepositor.length; i++) {
                if (queuedDepositIndexesForDepositor[i] == oldIndex) {
                    queuedDepositIndexesForDepositor[i] = newIndex;
                    break;
                }
            }
        }
    }

    function _removeFromArray(
        DepositAutomatorStorage.QueuedDeposit[] storage array,
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

    function _queuedDeposit(
        address vault,
        uint index
    ) internal view returns (DepositAutomatorStorage.QueuedDeposit memory) {
        return
            DepositAutomatorStorage.layout().queuedDepositsByVault[vault][
                index
            ];
    }
}

