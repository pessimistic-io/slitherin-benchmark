// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8;

import "./IAspenFeatures.sol";
import "./IMulticallable.sol";
import "./IAspenVersioned.sol";
import "./ICedarSFTIssuance.sol";
import "./ISFTLimitSupply.sol";
import "./ISFTSupply.sol";
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

interface IAspenERC1155DropV1 is
    IAspenFeaturesV0,
    IAspenVersionedV2,
    IMulticallableV0,
    IPublicSFTIssuanceV2,
    ISFTSupplyV1,
    // NOTE: keep this standard interfaces around to generate supportsInterface
    IERC1155V2,
    IERC2981V0,
    IRestrictedERC4906V0,
    // NOTE: keep this standard interfaces around to generate supportsInterface ˆˆ
    IPublicRoyaltyV0,
    IPublicUpdateBaseURIV0,
    IPublicMetadataV0,
    IPublicOwnableV0,
    IAspenSFTMetadataV1,
    IPublicAgreementV1,
    IPublicPrimarySaleV1,
    IPublicPlatformFeeV0,
    IRestrictedAgreementV1,
    IDelegatedAgreementV0,
    IRestrictedSFTIssuanceV3,
    IRestrictedLazyMintV1,
    IRestrictedPausableV1,
    IRestrictedMetadataV2,
    IRestrictedUpdateBaseURIV1,
    IRestrictedRoyaltyV2,
    IRestrictedPrimarySaleV2,
    IRestrictedSFTLimitSupplyV1,
    IRestrictedOwnableV0,
    IRestrictedPlatformFeeV0
{}

