// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8;

import "./IAspenFeatures.sol";
import "./IMulticallable.sol";
import "./IAspenVersioned.sol";
import "./ICedarNFTIssuance.sol";
import "./INFTLimitSupply.sol";
import "./IAgreement.sol";
import "./INFTSupply.sol";
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

interface IAspenERC721DropV1 is
    IAspenFeaturesV0,
    IAspenVersionedV2,
    IMulticallableV0,
    IPublicNFTIssuanceV2,
    INFTSupplyV1,
    // NOTE: keep this standard interfaces around to generate supportsInterface
    IERC721V2,
    IERC2981V0,
    IRestrictedERC4906V0,
    // NOTE: keep this standard interfaces around to generate supportsInterface ˆˆ
    IPublicRoyaltyV0,
    IPublicUpdateBaseURIV0,
    IPublicMetadataV0,
    IPublicOwnableV0,
    IAspenNFTMetadataV1,
    IPublicAgreementV1,
    IPublicPrimarySaleV1,
    IPublicPlatformFeeV0,
    IRestrictedAgreementV1,
    IDelegatedAgreementV0,
    IRestrictedNFTIssuanceV3,
    IRestrictedLazyMintV1,
    IRestrictedPausableV1,
    IRestrictedMetadataV2,
    IRestrictedUpdateBaseURIV1,
    IRestrictedRoyaltyV2,
    IRestrictedPrimarySaleV2,
    IRestrictedNFTLimitSupplyV1,
    IRestrictedOwnableV0,
    IRestrictedPlatformFeeV0
{

}

