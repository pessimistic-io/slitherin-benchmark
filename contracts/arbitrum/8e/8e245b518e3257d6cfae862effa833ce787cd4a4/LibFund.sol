// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IGetters} from "./IGetters.sol";

import {EnumerableSet} from "./EnumerableSet.sol";
import {LibTermStorage} from "./LibTermStorage.sol";
import {LibFundStorage} from "./LibFundStorage.sol";

library LibFund {
    using EnumerableSet for EnumerableSet.AddressSet;

    event OnTermStart(uint indexed termId); // Emits when a new term starts, this also marks the start of the first cycle
    event OnFundStateChanged(
        uint indexed termId,
        uint indexed currentCycle,
        LibFundStorage.FundStates indexed newState
    ); // Emits when state has updated
    event OnPaidContribution(uint indexed termId, address indexed payer, uint indexed currentCycle); // Emits when participant pays the contribution

    /// @notice called by the term to init the fund
    /// @param termId the id of the term
    function _initFund(uint termId) internal {
        LibFundStorage.Fund storage fund = LibFundStorage._fundStorage().funds[termId];
        uint participantsArrayLength = fund.beneficiariesOrder.length;
        // Set and track participants
        for (uint i; i < participantsArrayLength; ) {
            EnumerableSet.add(fund._participants, fund.beneficiariesOrder[i]);
            fund.isParticipant[fund.beneficiariesOrder[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Starts the first cycle
        _startNewCycle(termId);

        // Set timestamp of deployment, which will be used to determine cycle times
        // We do this after starting the first cycle to make sure the first cycle starts smoothly
        fund.fundStart = block.timestamp;
        //emit LibFund.OnTermStart(termId);
        emit OnTermStart(termId);
    }

    /// @notice This starts the new cycle and can only be called internally. Used upon deploy
    /// @param _termId The id of the term
    function _startNewCycle(uint _termId) internal {
        LibFundStorage.Fund storage fund = LibFundStorage._fundStorage().funds[_termId];
        LibTermStorage.Term storage term = LibTermStorage._termStorage().terms[_termId];
        // currentCycle is 0 when this is called for the first time
        require(
            block.timestamp > term.cycleTime * fund.currentCycle + fund.fundStart,
            "Too early to start new cycle"
        );
        require(
            fund.currentState == LibFundStorage.FundStates.InitializingFund ||
                fund.currentState == LibFundStorage.FundStates.CycleOngoing,
            "Wrong state"
        );

        ++fund.currentCycle;
        uint length = fund.beneficiariesOrder.length;
        for (uint i; i < length; ) {
            fund.paidThisCycle[fund.beneficiariesOrder[i]] = false;
            unchecked {
                ++i;
            }
        }

        _setState(_termId, LibFundStorage.FundStates.AcceptingContributions);

        // We attempt to make the autopayers pay their contribution right away
        _autoPay(_termId);
    }

    /// @notice updates the state according to the input and makes sure the state can't be changed if the fund is closed. Also emits an event that this happened
    /// @param _termId The id of the term
    /// @param _newState The new state of the fund
    function _setState(uint _termId, LibFundStorage.FundStates _newState) internal {
        LibFundStorage.Fund storage fund = LibFundStorage._fundStorage().funds[_termId];
        require(fund.currentState != LibFundStorage.FundStates.FundClosed, "Fund closed");
        fund.currentState = _newState;
        emit OnFundStateChanged(_termId, fund.currentCycle, _newState);
    }

    /// @notice function to attempt to make autopayers pay their contribution
    /// @param _termId the id of the term
    function _autoPay(uint _termId) internal {
        LibFundStorage.Fund storage fund = LibFundStorage._fundStorage().funds[_termId];

        // Get the beneficiary for this cycle
        address currentBeneficiary = IGetters(address(this)).getCurrentBeneficiary(_termId);

        address[] memory autoPayers = fund.beneficiariesOrder; // use beneficiariesOrder because it is a single array with all participants
        uint autoPayersArray = autoPayers.length;

        for (uint i; i < autoPayersArray; ) {
            address autoPayer = autoPayers[i];
            // The beneficiary doesn't pay
            if (currentBeneficiary == autoPayer) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (
                fund.autoPayEnabled[autoPayer] &&
                !fund.paidThisCycle[autoPayer] &&
                !fund.isExemptedOnCycle[fund.currentCycle].exempted[autoPayer]
            ) {
                _payContributionSafe(_termId, autoPayer, autoPayer);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice function to pay the actual contribution for the cycle, used for autopay to prevent reverts
    /// @param _termId the id of the term
    /// @param _payer the address that's paying
    /// @param _participant the (participant) address that's being paid for
    function _payContributionSafe(uint _termId, address _payer, address _participant) internal {
        LibFundStorage.Fund storage fund = LibFundStorage._fundStorage().funds[_termId];
        LibTermStorage.Term storage term = LibTermStorage._termStorage().terms[_termId];

        // Get the amount and do the actual transfer
        // This will only succeed if the sender approved this contract address beforehand
        uint amount = term.contributionAmount * 10 ** 6; // Deducted from user's wallet, six decimals
        try fund.stableToken.transferFrom(_payer, address(this), amount) returns (bool success) {
            if (success) {
                // Finish up, set that the participant paid for this cycle and emit an event that it's been done
                fund.paidThisCycle[_participant] = true;
                emit OnPaidContribution(_termId, _participant, fund.currentCycle);
            }
        } catch {}
    }
}

