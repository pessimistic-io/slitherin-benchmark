// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, IAgreementManager, IERC165} from "./Term.sol";
import {Right} from "./Right.sol";
import {IDelayedCancellation} from "./IDelayedCancellation.sol";

/// @notice Agreement Term controls cancellation with grace period.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/DelayedCancellation.sol)
contract DelayedCancellation is Right, IDelayedCancellation {
    /// @dev Storage of DelayedCancellation Terms Data by Manager Contract and Agreement ID
    mapping(IAgreementManager => mapping(uint256 => DelayedCancellationTerm)) public cancellationData;

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        uint256 gracePeriod = abi.decode(data, (uint256));
        if (gracePeriod == 0) revert Term__ZeroValue();

        cancellationData[manager][tokenId] = DelayedCancellationTerm({cancelInitiatedAt: 0, gracePeriod: gracePeriod});
    }

    function _settleTerm(IAgreementManager, uint256) internal virtual override {}

    function _cancelTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        DelayedCancellationTerm memory term = cancellationData[manager][tokenId];
        if (term.cancelInitiatedAt == 0) revert DelayedCancellation__CancelNotInitiated();
        if (block.timestamp < (term.cancelInitiatedAt + term.gracePeriod))
            revert DelayedCancellation__GracePeriodActive();
    }

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete cancellationData[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    /// @inheritdoc IDelayedCancellation
    function initiateCancellation(IAgreementManager manager, uint256 tokenId) public virtual override {
        if (msg.sender != manager.issuer(tokenId)) revert Term__NotIssuer(msg.sender);

        cancellationData[manager][tokenId].cancelInitiatedAt = block.timestamp;

        emit CancelInitiated(manager, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Term) returns (bool) {
        return interfaceId == type(IDelayedCancellation).interfaceId || super.supportsInterface(interfaceId);
    }
}

