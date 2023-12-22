// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./UnboundBase.sol";

import "./IAccountManager.sol";
import "./Initializable.sol";

contract HintHelpers is UnboundBase, Initializable{

    IAccountManager public accountManager;

    function initialize(
        address _accountManager,
        address _sortedAccounts
    ) public initializer {
        accountManager = IAccountManager(_accountManager);
        sortedAccounts = ISortedAccounts(_sortedAccounts);
        MCR = accountManager.MCR();
    }

    // --- Functions ---

    /* getRedemptionHints() - Helper function for finding the right hints to pass to redeemCollateral().
     *
     * It simulates a redemption of `_UNDamount` to figure out where the redemption sequence will start and what state the final Account
     * of the sequence will end up in.
     *
     * Returns three hints:
     *  - `firstRedemptionHint` is the address of the first Account with ICR >= MCR (i.e. the first Account that will be redeemed).
     *  - `partialRedemptionHintNICR` is the final nominal ICR of the last Account of the sequence after being hit by partial redemption,
     *     or zero in case of no partial redemption.
     *  - `truncatedUNDamount` is the maximum amount that can be redeemed out of the the provided `_UNDamount`. This can be lower than
     *    `_UNDamount` when redeeming the full amount would leave the last Account of the redemption sequence with less net debt than the
     *    minimum allowed value (i.e. MIN_NET_DEBT).
     *
     * The number of Accounts to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero
     * will leave it uncapped.
     */

    function getRedemptionHints(
        uint _UNDamount, 
        uint _price,
        uint _maxIterations
    )
        external
        view
        returns (
            address firstRedemptionHint,
            uint partialRedemptionHintNICR,
            uint truncatedUNDamount
        )
    {
        ISortedAccounts sortedAccountsCached = sortedAccounts;

        uint remainingUND = _UNDamount;
        address currentAccountuser = sortedAccountsCached.getLast();

        while (currentAccountuser != address(0) && accountManager.getCurrentICR(currentAccountuser, _price) < MCR) {
            currentAccountuser = sortedAccountsCached.getPrev(currentAccountuser);
        }

        firstRedemptionHint = currentAccountuser;

        if (_maxIterations == 0) {
            _maxIterations = type(uint256).max;
        }

        while (currentAccountuser != address(0) && remainingUND > 0 && _maxIterations > 0) {
            uint netUNDDebt = accountManager.getAccountDebt(currentAccountuser);
            if (netUNDDebt > remainingUND) {
                if (netUNDDebt > MIN_NET_DEBT) {
                    uint maxRedeemableUND = UnboundMath._min(remainingUND, netUNDDebt - MIN_NET_DEBT);

                    uint Collateral = accountManager.getAccountColl(currentAccountuser);

                    uint newColl = Collateral - ((maxRedeemableUND * DECIMAL_PRECISION) / _price);
                    uint newDebt = netUNDDebt - maxRedeemableUND;

                    partialRedemptionHintNICR = UnboundMath._computeNominalCR(newColl, newDebt);

                    remainingUND = remainingUND - maxRedeemableUND;

                }
                break;
            } else {
                remainingUND = remainingUND - netUNDDebt;
            }

            currentAccountuser = sortedAccountsCached.getPrev(currentAccountuser);
            _maxIterations--;
        }

        truncatedUNDamount = _UNDamount - remainingUND;
    }


    /* getApproxHint() - return address of a Account that is, on average, (length / numTrials) positions away in the 
    sortedAccounts list from the correct insert position of the Account to be inserted. 
    
    Note: The output address is worst-case O(n) positions away from the correct insert position, however, the function 
    is probabilistic. Input can be tuned to guarantee results to a high degree of confidence, e.g:

    Submitting numTrials = k * sqrt(length), with k = 15 makes it very, very likely that the ouput address will 
    be <= sqrt(length) positions away from the correct insert position.
    */

    function getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)
        external
        view
        returns (address hintAddress, uint diff, uint latestRandomSeed)
    {
        uint arrayLength = accountManager.getAccountOwnersCount();

        if (arrayLength == 0) {
            return (address(0), 0, _inputRandomSeed);
        }

        hintAddress = sortedAccounts.getLast();
        diff = UnboundMath._getAbsoluteDifference(_CR, accountManager.getNominalICR(hintAddress));
        latestRandomSeed = _inputRandomSeed;

        uint i = 1;

        while (i < _numTrials) {
            latestRandomSeed = uint(keccak256(abi.encodePacked(latestRandomSeed)));

            uint arrayIndex = latestRandomSeed % arrayLength;
            address currentAddress = accountManager.getAccountFromAccountOwnersArray(arrayIndex);
            uint currentNICR = accountManager.getNominalICR(currentAddress);

            // check if abs(current - CR) > abs(closest - CR), and update closest if current is closer
            uint currentDiff = UnboundMath._getAbsoluteDifference(currentNICR, _CR);

            if (currentDiff < diff) {
                diff = currentDiff;
                hintAddress = currentAddress;
            }
            i++;
        }

    }

    function computeNominalCR(uint _coll, uint _debt) external pure returns (uint) {
        return UnboundMath._computeNominalCR(_coll, _debt);
    }

    function computeCR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return UnboundMath._computeCR(_coll, _debt, _price);
    }
}
