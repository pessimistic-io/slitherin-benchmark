// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IRebornDefinition} from "./IRebornPortal.sol";
import {IRebornToken} from "./IRebornToken.sol";
import {IRewardVault} from "./IRewardVault.sol";
import {BitMapsUpgradeable} from "./BitMapsUpgradeable.sol";
import {PortalLib} from "./PortalLib.sol";
import {IPiggyBank} from "./IPiggyBank.sol";
import {IAirdropVault} from "./IAirdropVault.sol";
import {IRegistry} from "./IRegistry.sol";

abstract contract RebornPortalStorage is IRebornDefinition {
    //########### Link Contract Address ########## //
    IRebornToken private rebornToken;
    IRewardVault public vault;
    address public burnPool;
    IPiggyBank private piggyBank;

    uint256 internal _season;

    //#### Access #####//
    mapping(address => bool) private signers;

    //#### Incarnation ######//
    uint256 internal idx;
    mapping(address => uint256) internal rounds;
    mapping(uint256 => LifeDetail) internal details;
    BitMapsUpgradeable.BitMap internal _seeds;
    // season => user address => count
    mapping(uint256 => mapping(address => uint256)) internal _incarnateCounts;
    // max incarnation count
    uint256 internal _incarnateCountLimit;

    //##### Tribute ###### //
    mapping(uint256 => SeasonData) internal _seasonData;

    //#### Refer #######//
    mapping(address => address) internal referrals;
    PortalLib.ReferrerRewardFees internal rewardFees;

    //#### airdrop config #####//
    AirdropConf private _dropConf;
    VrfConf private _vrfConf;
    // requestId => request status
    mapping(uint256 => RequestStatus) private _vrfRequests;
    uint256[3] private _placeholder2;

    //########### NFT ############//
    // tokenId => character property
    mapping(uint256 => PortalLib.CharacterProperty)
        internal _characterProperties;
    // tokenId => token amount required
    mapping(uint256 => uint256) internal _forgeRequiredMaterials;

    //######### Piggy Bank #########//
    // X% to piggyBank piggyBankFee / 10000
    uint256 internal piggyBankFee;

    // airdrop vault
    IAirdropVault public airdropVault;

    mapping(address => AirDropDebt) internal _airdropDebt;

    bytes32 internal _dropNativeRoot;
    bytes32 internal _dropDegenRoot;

    IRegistry public _registry;
    uint96 internal _placeholder;

    // tokenId => exhumed count
    mapping(uint256 => uint256) internal _exhumeCount;

    mapping(address => mapping(RewardToClaimType => RewardStore))
        internal _rewardToClaim;

    mapping(address => uint256) internal _claimRewardNonce;

    /// @dev gap for potential variable
    uint256[19] private _gap;
}

