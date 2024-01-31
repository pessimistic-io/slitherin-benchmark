// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8;

import "./IAspenFeatures.sol";
import "./IMulticallable.sol";
import "./IAspenVersioned.sol";
import "./ICedarNFTIssuance.sol";
import "./INFTLimitSupply.sol";
import "./IAgreement.sol";
import "./INFTSupply.sol";
import "./INFTClaimCount.sol";
import "./ILazyMint.sol";
import "./IERC721.sol";
import "./IERC4906.sol";
import "./IERC2981.sol";
import "./IRoyalty.sol";
import "./IUpdateBaseURI.sol";
import "./INFTMetadata.sol";
import "./IContractMetadata.sol";
import "./IPrimarySale.sol";
import "./IPausable.sol";
import "./IOwnable.sol";
import "./IPlatformFee.sol";

// Each AspenERC721 contract should implement a maximal version of the interfaces it supports and should itself carry
// the version major version suffix, in this case CedarERC721V0

interface IAspenERC721DropV2 is
    IAspenFeaturesV0,
    IAspenVersionedV2,
    IMulticallableV0,
    // NOTE: keep this standard interfaces around to generate supportsInterface
    IERC721V3,
    IERC2981V0,
    IRestrictedERC4906V0,
    // NOTE: keep this standard interfaces around to generate supportsInterface ˆˆ
    // Supply
    INFTSupplyV1,
    IRestrictedNFTLimitSupplyV1,
    // Issuance
    IPublicNFTIssuanceV4,
    IDelegatedNFTIssuanceV0,
    IRestrictedNFTIssuanceV4,
    // Roylaties
    IPublicRoyaltyV0,
    IRestrictedRoyaltyV1,
    // BaseUri
    IPublicUpdateBaseURIV0,
    IRestrictedUpdateBaseURIV1,
    // Metadata
    IPublicMetadataV0,
    IAspenNFTMetadataV1,
    IRestrictedMetadataV2,
    // Ownable
    IPublicOwnableV0,
    IRestrictedOwnableV0,
    // Pausable
    IPublicPausableV0,
    IRestrictedPausableV1,
    // Agreement
    IPublicAgreementV1,
    IDelegatedAgreementV0,
    IRestrictedAgreementV1,
    // Primary Sale
    IPublicPrimarySaleV1,
    IRestrictedPrimarySaleV2,
    // Oprator Filterers
    IRestrictedOperatorFiltererV0,
    IPublicOperatorFilterToggleV0,
    IRestrictedOperatorFilterToggleV0,
    // Delegated only
    IDelegatedPlatformFeeV0,
    // Restricted only
    IRestrictedLazyMintV1,
    IRestrictedNFTClaimCountV0
{

}

