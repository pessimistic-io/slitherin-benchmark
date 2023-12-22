// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, ITerm, IERC165} from "./Term.sol";
import {IVesting, CompletionSchedule, IAgreementManager} from "./IVesting.sol";

/// @notice Agreement Term applying constraints according to a fixed schedule.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Vesting.sol)
contract Vesting is Term, IVesting {
    using CompletionSchedule for CompletionSchedule.Schedule;

    /// @dev Storage of Vesting Terms by Agreement ID
    mapping(IAgreementManager => mapping(uint256 => CompletionSchedule.Schedule)) internal vestingData;

    function getSchedule(IAgreementManager manager, uint256 agreementId)
        public
        view
        virtual
        override
        returns (CompletionSchedule.Schedule memory)
    {
        return vestingData[manager][agreementId];
    }

    function constraintStatus(IAgreementManager manager, uint256 tokenId)
        public
        view
        virtual
        override(Term, ITerm)
        returns (uint256)
    {
        return vestingData[manager][tokenId].percentageAt(block.timestamp);
    }

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        // Encoding structs with multiple dynamic arrays is not supported
        // Arrays are decoded here explicitly rather than into the struct
        (uint256[] memory times, uint256[] memory percentages) = abi.decode(data, (uint256[], uint256[]));
        CompletionSchedule.Schedule memory schedule = CompletionSchedule.Schedule({
            times: times,
            percentages: percentages
        });
        CompletionSchedule.verifySchedule(schedule);
        if (times[times.length - 1] > manager.expiration(tokenId)) revert Vesting__TimeOutOfBounds();

        vestingData[manager][tokenId] = schedule;
    }

    function _settleTerm(IAgreementManager, uint256) internal virtual override {}

    function _cancelTerm(IAgreementManager, uint256) internal virtual override {}

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete vestingData[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Term) returns (bool) {
        return interfaceId == type(IVesting).interfaceId || super.supportsInterface(interfaceId);
    }
}

