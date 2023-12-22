//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ITreasureClaimer, ClaimInfo } from "./ITreasureClaimer.sol";
import { ITreasureBadges } from "./ITreasureBadges.sol";
import { UtilitiesUpgradeable, Initializable } from "./UtilitiesUpgradeable.sol";

abstract contract TreasureClaimerState is Initializable, ITreasureClaimer, UtilitiesUpgradeable {
    bytes32 public constant CLAIMINFO_TYPE_HASH = keccak256(
        "ClaimInfo(address claimer,address badgeAddress,uint256 badgeId,bytes32 nonce,uint256 priceInUSD,address paymentToken)"
    );

    address public signingAuthority;
    ITreasureBadges public treasureBadgeCollection;

    // Maps userAddress -> badgeAddress -> badgeId -> nonce -> isClaimed status.
    mapping(address => mapping(address => mapping(uint256 => mapping(bytes32 => bool)))) public claimInfoIsClaimed;

    address public spellcaster;

    function __TreasureClaimerState_init() internal onlyInitializing {
        __Utilities_init();
    }
}

interface IPayments {
    enum PriceType {
        STATIC,
        PRICED_IN_ERC20,
        PRICED_IN_USD,
        PRICED_IN_GAS_TOKEN
    }

    function calculatePaymentAmountByPriceType(
        address _paymentToken,
        uint256 _paymentAmountInPricedToken,
        PriceType _priceType,
        address _pricedERC20
    ) external view returns (uint256 paymentAmount_);
    function getMagicAddress() external view returns (address magicAddress_);
}

