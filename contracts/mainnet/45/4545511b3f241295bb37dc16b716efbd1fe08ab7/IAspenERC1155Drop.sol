// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8;

import "./IAspenFeatures.sol";
import "./IMulticallable.sol";
import "./IAspenVersioned.sol";
import "./ICedarSFTIssuance.sol";
import "./ISFTLimitSupply.sol";
import "./ISFTSupply.sol";
import "./ISFTClaimCount.sol";
import "./IUpdateBaseURI.sol";
import "./IERC1155.sol";
import "./IERC2981.sol";
import "./IERC4906.sol";
import "./IRoyalty.sol";
import "./ISFTMetadata.sol";
import "./IContractMetadata.sol";
import "./IAgreement.sol";
import "./IPrimarySale.sol";
import "./ILazyMint.sol";
import "./IPausable.sol";
import "./IOwnable.sol";
import "./IPlatformFee.sol";

interface IAspenERC1155DropV2 is
    IAspenFeaturesV0,
    IAspenVersionedV2,
    IMulticallableV0,
    // NOTE: keep this standard interfaces around to generate supportsInterface
    IERC1155V3,
    IERC2981V0,
    IRestrictedERC4906V0,
    // NOTE: keep this standard interfaces around to generate supportsInterface ˆˆ
    // Supply
    IPublicSFTSupplyV0,
    IDelegatedSFTSupplyV0,
    IRestrictedSFTLimitSupplyV1,
    // Issuance
    IPublicSFTIssuanceV4,
    IDelegatedSFTIssuanceV0,
    IRestrictedSFTIssuanceV4,
    // Royalties
    IPublicRoyaltyV0,
    IRestrictedRoyaltyV1,
    // BaseUri
    IDelegatedUpdateBaseURIV0,
    IRestrictedUpdateBaseURIV1,
    // Metadata
    IPublicMetadataV0,
    IRestrictedMetadataV2,
    IAspenSFTMetadataV1,
    // Ownable
    IPublicOwnableV0,
    IRestrictedOwnableV0,
    // Pausable
    IDelegatedPausableV0,
    IRestrictedPausableV1,
    // Agreement
    IPublicAgreementV1,
    IDelegatedAgreementV0,
    IRestrictedAgreementV1,
    // Primary Sale
    IPublicPrimarySaleV1,
    IRestrictedPrimarySaleV2,
    IRestrictedSFTPrimarySaleV0,
    // Operator Filterer
    IRestrictedOperatorFiltererV0,
    IPublicOperatorFilterToggleV0,
    IRestrictedOperatorFilterToggleV0,
    // Delegated only
    IDelegatedPlatformFeeV0,
    // Restricted Only
    IRestrictedLazyMintV1,
    IRestrictedSFTClaimCountV0
{}

