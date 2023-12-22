// SPDX-License-Identifier: NONE
pragma solidity 0.8.10;

import "./console.sol";

import {TokensFacet} from "./TokensFacet.sol";
import {WithStorage, WithModifiers} from "./LibStorage.sol";
import {LibTokens} from "./LibTokens.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import "./LibStorage.sol";

/**
 * Used to initialize values on our storages on deployment
 */

struct InitArgs {
    // == Constants == //
    string gen0EggUri;
    string baseUri;
    string contractUri;
    // == State variables == //
    address royaltiesRecipient;
    uint16 foundersPackUsdCost;
    uint256 foundersPackGasOffset;
    uint256 withdrawalGasOffset;
    uint256 royaltiesPercentage;
    uint256 nativeTokenPriceInUsd;
    bool paused;
    address[] adminAddresses;
    address forgerAddress;
    address borisAddress;
    address contractFundsRecipient;
    uint256 botsFeePercentage;
}

contract InitializerFacet is WithStorage, WithModifiers {
    using EnumerableSet for EnumerableSet.UintSet;

    function initialize(InitArgs memory args) external ownerOnly {
        _tc().gen0EggUri = args.gen0EggUri;
        _tc().baseUri = args.baseUri;
        _tc().contractUri = args.contractUri;
        _ts().royaltiesRecipient = args.royaltiesRecipient;
        _ts().royaltiesPercentage = args.royaltiesPercentage;
        _ts().seedPetsIndex = LibTokens.SEED_PETS_BASE_ID;
        _ts().eggsIndex = LibTokens.EGGS_BASE_ID;
        _ts().nftsIndex = LibTokens.NFTS_BASE_ID;
        _ts().resourcesIndex = LibTokens.RESOURCES_BASE_ID;
        _ts().fungiblesIndex = LibTokens.FUNGIBLES_BASE_ID;
        _ts().withdrawalGasOffset = args.withdrawalGasOffset;
        _ts().totalMintedEggs = 0;
        _ss().foundersPackUsdCost = args.foundersPackUsdCost;
        _ss().foundersPackGasOffset = args.foundersPackGasOffset;
        _acs().paused = args.paused;
        _ps().nativeTokenPriceInUsd = args.nativeTokenPriceInUsd;
        _ss().foundersPackPurchaseAllowed = true;
        _acs().contractFundsRecipient = args.contractFundsRecipient;
        _acs().forgerAddress = args.forgerAddress;
        _acs().borisAddress = args.borisAddress;
        _ss().botsFeePercentage = args.botsFeePercentage;

        for (uint256 i; i < args.adminAddresses.length; i++) {
            _acs().rolesByAddress[args.adminAddresses[i]].add(
                uint256(LibAccessControl.Roles.ADMIN)
            );
        }

        _acs().rolesByAddress[args.forgerAddress].add(
            uint256(LibAccessControl.Roles.FORGER)
        );

        _acs().rolesByAddress[args.borisAddress].add(
            uint256(LibAccessControl.Roles.BORIS)
        );
    }
}

