// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

import {IFund} from "./IFund.sol";
import {ICollateral} from "./ICollateral.sol";
import {IERC20} from "./IERC20.sol";
import {ITerm} from "./ITerm.sol";
import {IGetters} from "./IGetters.sol";
import {IYGFacetZaynFi} from "./IYGFacetZaynFi.sol";

import {LibFundStorage} from "./LibFundStorage.sol";
import {LibFund} from "./LibFund.sol";
import {LibTermStorage} from "./LibTermStorage.sol";
import {LibCollateral} from "./LibCollateral.sol";
import {LibCollateralStorage} from "./LibCollateralStorage.sol";
import {LibYieldGenerationStorage} from "./LibYieldGenerationStorage.sol";
import {LibYieldGeneration} from "./LibYieldGeneration.sol";

/// @title Takaturn Term
/// @author Mohammed Haddouti
/// @notice This is used to deploy the collateral & fund contracts
/// @dev v3.0 (Diamond)
contract TermFacet is ITerm {
    uint public constant TERM_VERSION = 2;

    event OnTermCreated(uint indexed termId, address indexed termOwner);
    event OnCollateralDeposited(uint indexed termId, address indexed user, uint amount);
    event OnTermFilled(uint indexed termId);
    event OnTermExpired(uint indexed termId);
    event OnTermStart(uint indexed termId); // Emits when a new term starts, this also marks the start of the first cycle

    function createTerm(
        uint totalParticipants,
        uint registrationPeriod,
        uint cycleTime,
        uint contributionAmount, // in stable token, without decimals
        uint contributionPeriod,
        address stableTokenAddress
    ) external returns (uint) {
        return
            _createTerm(
                totalParticipants,
                registrationPeriod,
                cycleTime,
                contributionAmount,
                contributionPeriod,
                stableTokenAddress
            );
    }

    function joinTerm(uint termId, bool optYield) external payable {
        _joinTerm(termId, optYield);
    }

    function startTerm(uint termId) external {
        _startTerm(termId);
    }

    function expireTerm(uint termId) external {
        _expireTerm(termId);
    }

    function _createTerm(
        uint _totalParticipants,
        uint _registrationPeriod,
        uint _cycleTime,
        uint _contributionAmount,
        uint _contributionPeriod,
        address _stableTokenAddress
    ) internal returns (uint) {
        require(
            _cycleTime != 0 &&
                _contributionAmount != 0 &&
                _contributionPeriod != 0 &&
                _totalParticipants != 0 &&
                _registrationPeriod != 0 &&
                _contributionPeriod < _cycleTime &&
                _stableTokenAddress != address(0),
            "Invalid inputs"
        );

        LibTermStorage.TermStorage storage termStorage = LibTermStorage._termStorage();
        uint termId = termStorage.nextTermId;

        LibTermStorage.Term memory newTerm;

        newTerm.termId = termId;
        newTerm.totalParticipants = _totalParticipants;
        newTerm.registrationPeriod = _registrationPeriod;
        newTerm.cycleTime = _cycleTime;
        newTerm.contributionAmount = _contributionAmount; // stored without decimals
        newTerm.contributionPeriod = _contributionPeriod;
        newTerm.stableTokenAddress = _stableTokenAddress;
        newTerm.termOwner = msg.sender;
        newTerm.creationTime = block.timestamp;
        newTerm.initialized = true;
        newTerm.state = LibTermStorage.TermStates.InitializingTerm;

        termStorage.terms[termId] = newTerm;
        termStorage.nextTermId++;

        _createCollateral(termId, _totalParticipants);

        emit OnTermCreated(termId, msg.sender);

        return termId;
    }

    function _joinTerm(uint _termId, bool _optYield) internal {
        LibTermStorage.TermStorage storage termStorage = LibTermStorage._termStorage();
        LibTermStorage.Term memory term = termStorage.terms[_termId];
        LibCollateralStorage.Collateral storage collateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[_termId];
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[_termId];

        require(LibTermStorage._termExists(_termId), "Term doesn't exist");

        require(
            collateral.state == LibCollateralStorage.CollateralStates.AcceptingCollateral,
            "Closed"
        );

        require(collateral.counterMembers < term.totalParticipants, "No space");

        require(!collateral.isCollateralMember[msg.sender], "Reentry");

        uint memberIndex = collateral.counterMembers;

        uint minAmount = IGetters(address(this)).minCollateralToDeposit(_termId, memberIndex);
        require(msg.value >= minAmount, "Eth payment too low");

        collateral.collateralMembersBank[msg.sender] += msg.value;
        collateral.isCollateralMember[msg.sender] = true;
        collateral.depositors[memberIndex] = msg.sender;
        collateral.counterMembers++;
        collateral.collateralDepositByUser[msg.sender] += msg.value;

        termStorage.participantToTermId[msg.sender].push(_termId);

        // If the lock is false, I accept the opt in
        if (!LibYieldGenerationStorage._yieldLock().yieldLock) {
            yield.hasOptedIn[msg.sender] = _optYield;
        } else {
            // If the lock is true, opt in is always false
            yield.hasOptedIn[msg.sender] = false;
        }

        emit OnCollateralDeposited(_termId, msg.sender, msg.value);

        if (collateral.counterMembers == 1) {
            collateral.firstDepositTime = block.timestamp;
        }

        // If all the spots are filled, change the collateral
        if (collateral.counterMembers == term.totalParticipants) {
            emit OnTermFilled(_termId);
        }
    }

    function _startTerm(uint _termId) internal {
        LibTermStorage.Term storage term = LibTermStorage._termStorage().terms[_termId];
        LibCollateralStorage.Collateral storage collateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[_termId];
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[_termId];
        address[] memory depositors = collateral.depositors;

        uint depositorsArrayLength = depositors.length;

        require(
            block.timestamp > collateral.firstDepositTime + term.registrationPeriod,
            "Term not ready to start"
        );

        require(collateral.counterMembers == term.totalParticipants, "All spots are not filled");

        // Need to check each user because they can have different collateral amounts
        for (uint i; i < depositorsArrayLength; ) {
            require(
                !ICollateral(address(this)).isUnderCollaterized(term.termId, depositors[i]),
                "Eth prices dropped"
            );

            unchecked {
                ++i;
            }
        }

        // Actually create and initialize the fund
        _createFund(term, collateral);

        // If the lock is false
        if (!LibYieldGenerationStorage._yieldLock().yieldLock) {
            // Check on each depositor if they opted in for yield generation
            for (uint i; i < depositorsArrayLength; ) {
                if (yield.hasOptedIn[depositors[i]]) {
                    // If someone opted in, create the yield generator
                    _createYieldGenerator(term, collateral);
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }

        // Tell the collateral that the term has started
        LibCollateral._setState(term.termId, LibCollateralStorage.CollateralStates.CycleOngoing);

        term.state = LibTermStorage.TermStates.ActiveTerm;
    }

    function _createCollateral(uint _termId, uint _totalParticipants) internal {
        //require(!LibCollateralStorage._collateralExists(termId), "Collateral already exists");
        LibCollateralStorage.Collateral storage newCollateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[_termId];

        newCollateral.initialized = true;
        newCollateral.state = LibCollateralStorage.CollateralStates.AcceptingCollateral;
        newCollateral.depositors = new address[](_totalParticipants);
    }

    function _createFund(
        LibTermStorage.Term memory _term,
        LibCollateralStorage.Collateral storage _collateral
    ) internal {
        require(!LibFundStorage._fundExists(_term.termId), "Fund already exists");
        LibFundStorage.Fund storage newFund = LibFundStorage._fundStorage().funds[_term.termId];

        newFund.stableToken = IERC20(_term.stableTokenAddress);
        newFund.beneficiariesOrder = _collateral.depositors;
        newFund.initialized = true;
        newFund.totalAmountOfCycles = newFund.beneficiariesOrder.length;
        newFund.currentState = LibFundStorage.FundStates.InitializingFund;

        LibFund._initFund(_term.termId);
    }

    function _expireTerm(uint _termId) internal {
        LibTermStorage.Term storage term = LibTermStorage._termStorage().terms[_termId];
        LibCollateralStorage.Collateral storage collateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[_termId];

        require(
            LibTermStorage._termExists(_termId) && LibCollateralStorage._collateralExists(_termId)
        );

        require(
            collateral.firstDepositTime != 0 &&
                block.timestamp > collateral.firstDepositTime + term.registrationPeriod,
            "Registration period not ended"
        );

        require(
            collateral.counterMembers < term.totalParticipants,
            "All spots are filled, can't expire"
        );

        require(term.state != LibTermStorage.TermStates.ExpiredTerm, "Term already expired");

        uint depositorsArrayLength = collateral.depositors.length;

        for (uint i; i < depositorsArrayLength; ) {
            address depositor = collateral.depositors[i];

            if (depositor != address(0)) {
                uint amount = collateral.collateralMembersBank[depositor];

                collateral.collateralPaymentBank[depositor] += amount;
                collateral.collateralMembersBank[depositor] = 0;
                collateral.isCollateralMember[depositor] = false;
                collateral.depositors[i] = address(0);
                --collateral.counterMembers;
            }

            unchecked {
                ++i;
            }
        }

        term.state = LibTermStorage.TermStates.ExpiredTerm;
        collateral.initialized = false;
        collateral.state = LibCollateralStorage.CollateralStates.Closed;

        emit OnTermExpired(_termId);
    }

    function _createYieldGenerator(
        LibTermStorage.Term memory _term,
        LibCollateralStorage.Collateral storage _collateral
    ) internal {
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[_term.termId];
        LibYieldGenerationStorage.YieldProviders storage yieldProviders = LibYieldGenerationStorage
            ._yieldProviders();

        uint amountDeposited;

        address[] memory depositors = _collateral.depositors;
        uint depositorsArrayLength = depositors.length;

        for (uint i; i < depositorsArrayLength; ) {
            if (yield.hasOptedIn[depositors[i]]) {
                yield.yieldUsers.push(depositors[i]);
                amountDeposited += _collateral.collateralMembersBank[depositors[i]];
            }

            unchecked {
                ++i;
            }
        }

        if (amountDeposited > 0) {
            yield.startTimeStamp = block.timestamp;
            yield.initialized = true;
            yield.providerAddresses["ZaynZap"] = yieldProviders.providerAddresses["ZaynZap"];
            yield.providerAddresses["ZaynVault"] = yieldProviders.providerAddresses["ZaynVault"];

            LibYieldGeneration._depositYG(_term.termId, amountDeposited);
        }
    }
}

