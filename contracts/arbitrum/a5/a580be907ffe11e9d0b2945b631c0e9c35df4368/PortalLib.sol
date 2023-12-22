// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import {IRebornDefinition} from "./IRebornPortal.sol";
import {IERC721} from "./IERC721.sol";
import {RewardVault} from "./RewardVault.sol";
import {CommonError} from "./CommonError.sol";
import {ECDSAUpgradeable} from "./ECDSAUpgradeable.sol";
import {AirdropVault} from "./AirdropVault.sol";
import {Registry} from "./Registry.sol";

library PortalLib {
    uint256 public constant PERSHARE_BASE = 10e18;
    // percentage base of refer reward fees
    uint256 public constant PERCENTAGE_BASE = 10000;

    bytes32 public constant _SOUPPARAMS_TYPEHASH =
        keccak256(
            "AuthenticateSoupArg(address user,uint256 soupPrice,uint256 incarnateCounter,uint256 tokenId,uint256 deadline)"
        );

    bytes32 public constant _EXHUME_TYPEHASH =
        keccak256(
            "ExhumeArg(address exhumer,address exhumee,uint256 tokenId,uint256 nonce,uint256 nativeCost,uint256 degenCost,uint256 shovelTokenId,uint256 deadline)"
        );

    bytes32 public constant _CLAIM_TYPEHASH =
        keccak256(
            "ClaimRewardArg(address user,uint256 amount,uint256 type,uint256 nonce,uint256 deadline)"
        );

    bytes32 public constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    uint256 public constant ONE_HUNDRED = 100;

    struct CharacterParams {
        uint256 maxAP;
        uint256 restoreTimePerAP;
        uint256 level;
    }

    // TODO: use more compact storage
    struct CharacterProperty {
        uint8 currentAP;
        uint8 maxAP;
        uint24 restoreTimePerAP; // Time Needed to Restore One Action Point
        uint32 lastTimeAPUpdate;
        uint8 level;
    }

    struct CurrentAPReturn {
        uint256 currentAP;
        uint256 lastAPUpdateTime;
    }

    enum RewardType {
        NativeToken,
        RebornToken
    }

    struct ReferrerRewardFees {
        uint16 incarnateRef1Fee;
        uint16 incarnateRef2Fee;
        uint16 vaultRef1Fee;
        uint16 vaultRef2Fee;
        uint192 _slotPlaceholder;
    }

    struct Pool {
        uint256 totalAmount;
        uint256 accRebornPerShare;
        uint256 accNativePerShare;
        uint128 droppedRebornTotal;
        uint128 droppedNativeTotal;
        uint256 coindayCumulant;
        uint32 coindayUpdateLastTime;
        uint112 totalForwardTribute;
        uint112 totalReverseTribute;
        uint32 lastDropNativeTime;
        uint32 lastDropRebornTime;
        uint128 validTVL;
        uint64 placeholder;
    }

    //
    // We do some fancy math here. Basically, any point in time, the amount
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (Amount * pool.accPerShare) - user.rewardDebt
    //
    // Whenever a user infuse or switchPool. Here's what happens:
    //   1. The pool's `accPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
    struct Portfolio {
        uint256 accumulativeAmount;
        uint128 rebornRewardDebt;
        uint128 nativeRewardDebt;
        /// @dev reward for holding the NFT when the NFT is selected
        uint128 pendingOwnerRebornReward;
        uint128 pendingOwnerNativeReward;
        uint256 coindayCumulant;
        uint32 coindayUpdateLastTime;
        uint112 totalForwardTribute;
        uint112 totalReverseTribute;
    }

    event SignerUpdate(address signer, bool valid);
    event ReferReward(
        address indexed user,
        address indexed ref1,
        uint256 amount1,
        address indexed ref2,
        uint256 amount2,
        RewardType rewardType
    );

    function _toLastHour(uint256 timestamp) public pure returns (uint256) {
        return timestamp - (timestamp % (1 hours));
    }

    /**
     * @dev returns referrer and referrer reward
     * @return ref1  level1 of referrer. direct referrer
     * @return ref1Reward  level 1 referrer reward
     * @return ref2  level2 of referrer. referrer's referrer
     * @return ref2Reward  level 2 referrer reward
     */
    function _calculateReferReward(
        mapping(address => address) storage referrals,
        ReferrerRewardFees storage rewardFees,
        address account,
        uint256 amount,
        RewardType rewardType
    )
        public
        view
        returns (
            address ref1,
            uint256 ref1Reward,
            address ref2,
            uint256 ref2Reward
        )
    {
        ref1 = referrals[account];
        ref2 = referrals[ref1];

        if (rewardType == RewardType.NativeToken) {
            ref1Reward = ref1 == address(0)
                ? 0
                : (amount * rewardFees.incarnateRef1Fee) / PERCENTAGE_BASE;
            ref2Reward = ref2 == address(0)
                ? 0
                : (amount * rewardFees.incarnateRef2Fee) / PERCENTAGE_BASE;
        }

        if (rewardType == RewardType.RebornToken) {
            ref1Reward = ref1 == address(0)
                ? 0
                : (amount * rewardFees.vaultRef1Fee) / PERCENTAGE_BASE;
            ref2Reward = ref2 == address(0)
                ? 0
                : (amount * rewardFees.vaultRef2Fee) / PERCENTAGE_BASE;
        }
    }

    /**
     * @dev send NativeToken to referrers
     */
    function _sendNativeRewardToRefs(
        mapping(address => address) storage referrals,
        ReferrerRewardFees storage rewardFees,
        mapping(address => mapping(IRebornDefinition.RewardToClaimType => IRebornDefinition.RewardStore))
            storage _rewardToClaim,
        address account,
        uint256 amount
    ) public returns (uint256 total) {
        (
            address ref1,
            uint256 ref1Reward,
            address ref2,
            uint256 ref2Reward
        ) = _calculateReferReward(
                referrals,
                rewardFees,
                account,
                amount,
                RewardType.NativeToken
            );

        unchecked {
            _rewardToClaim[ref1][
                IRebornDefinition.RewardToClaimType.ReferNative
            ].totalReward += ref1Reward;
            _rewardToClaim[ref2][
                IRebornDefinition.RewardToClaimType.ReferNative
            ].totalReward += ref2Reward;
        }

        unchecked {
            total = ref1Reward + ref2Reward;
        }

        emit ReferReward(
            account,
            ref1,
            ref1Reward,
            ref2,
            ref2Reward,
            RewardType.NativeToken
        );
    }

    /**
     * @dev vault $REBORN token to referrers
     */
    function _rewardDegenRewardToRefs(
        mapping(address => address) storage referrals,
        ReferrerRewardFees storage rewardFees,
        mapping(address => mapping(IRebornDefinition.RewardToClaimType => IRebornDefinition.RewardStore))
            storage _rewardToClaim,
        address account,
        uint256 amount
    ) public {
        (
            address ref1,
            uint256 ref1Reward,
            address ref2,
            uint256 ref2Reward
        ) = _calculateReferReward(
                referrals,
                rewardFees,
                account,
                amount,
                RewardType.RebornToken
            );

        unchecked {
            _rewardToClaim[ref1][IRebornDefinition.RewardToClaimType.ReferDegen]
                .totalReward += ref1Reward;
            _rewardToClaim[ref2][IRebornDefinition.RewardToClaimType.ReferDegen]
                .totalReward += ref2Reward;
        }

        emit ReferReward(
            account,
            ref1,
            ref1Reward,
            ref2,
            ref2Reward,
            RewardType.RebornToken
        );
    }

    function _calculateCurrentAP(
        CharacterProperty memory charProperty
    ) public view returns (CurrentAPReturn memory) {
        // if restoreTimePerAP is not set, no process
        if (charProperty.restoreTimePerAP == 0) {
            return
                CurrentAPReturn(
                    charProperty.currentAP,
                    charProperty.lastTimeAPUpdate
                );
        }

        uint256 calculatedRestoreAp = (block.timestamp -
            charProperty.lastTimeAPUpdate) / charProperty.restoreTimePerAP;

        uint256 calculatedCurrentAP = calculatedRestoreAp +
            charProperty.currentAP;

        uint256 lastAPUpdateTime = charProperty.lastTimeAPUpdate +
            calculatedRestoreAp *
            charProperty.restoreTimePerAP;

        uint256 currentAP;

        // min(calculatedCurrentAP, maxAp)
        if (calculatedCurrentAP <= charProperty.maxAP) {
            currentAP = calculatedCurrentAP;
        } else {
            currentAP = charProperty.maxAP;
        }

        return CurrentAPReturn(currentAP, lastAPUpdateTime);
    }

    function _consumeAP(
        uint256 tokenId,
        mapping(uint256 => CharacterProperty) storage _characterProperties
    ) public {
        CharacterProperty storage charProperty = _characterProperties[tokenId];

        CurrentAPReturn memory car = _calculateCurrentAP(charProperty);

        // if current ap is max, recover starts from now
        if (car.currentAP == charProperty.maxAP) {
            charProperty.lastTimeAPUpdate = uint32(block.timestamp);
        } else {
            charProperty.lastTimeAPUpdate = uint32(car.lastAPUpdateTime);
        }

        // Reduce AP
        charProperty.currentAP = uint8(car.currentAP - 1);
    }

    function _useSoupParam(
        IRebornDefinition.SoupParams calldata soupParams,
        uint256 nonce,
        mapping(uint256 => PortalLib.CharacterProperty)
            storage _characterProperties,
        address registry
    ) public {
        _checkSoupSig(soupParams, nonce, registry);

        if (soupParams.charTokenId != 0) {
            // use degen2009 nft character
            _consumeAP(soupParams.charTokenId, _characterProperties);
        }
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _altarDomainSeparatorV4() public view returns (bytes32) {
        return
            _buildDomainSeparator(
                PortalLib._TYPE_HASH,
                keccak256("Altar"),
                keccak256("1")
            );
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _degenPortalDomainSeparatorV4() public view returns (bytes32) {
        return
            _buildDomainSeparator(
                PortalLib._TYPE_HASH,
                keccak256("DegenPortal"),
                keccak256("1")
            );
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    typeHash,
                    nameHash,
                    versionHash,
                    block.chainid,
                    address(this)
                )
            );
    }

    function _checkExhumeSig(
        IRebornDefinition.ExhumeParams calldata exhumeParams,
        uint256 nonce,
        address registry
    ) public view {
        if (block.timestamp >= exhumeParams.deadline) {
            revert CommonError.SignatureExpired();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                PortalLib._EXHUME_TYPEHASH,
                msg.sender,
                exhumeParams.exhumee,
                exhumeParams.tokenId,
                nonce,
                exhumeParams.nativeCost,
                exhumeParams.degenCost,
                exhumeParams.shovelTokenId,
                exhumeParams.deadline
            )
        );

        bytes32 hash = ECDSAUpgradeable.toTypedDataHash(
            _degenPortalDomainSeparatorV4(),
            structHash
        );

        address signer = ECDSAUpgradeable.recover(
            hash,
            exhumeParams.v,
            exhumeParams.r,
            exhumeParams.s
        );

        if (!Registry(registry).checkIsSigner(signer)) {
            revert CommonError.NotSigner();
        }
    }

    function _checkClaimRewardSig(
        IRebornDefinition.ClaimRewardParams calldata claimRewardParams,
        uint256 nonce,
        address registry
    ) public view {
        if (block.timestamp >= claimRewardParams.deadline) {
            revert CommonError.SignatureExpired();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                PortalLib._CLAIM_TYPEHASH,
                claimRewardParams.user,
                claimRewardParams.amount,
                claimRewardParams.t,
                nonce,
                claimRewardParams.deadline
            )
        );

        bytes32 hash = ECDSAUpgradeable.toTypedDataHash(
            _degenPortalDomainSeparatorV4(),
            structHash
        );

        address signer = ECDSAUpgradeable.recover(
            hash,
            claimRewardParams.v,
            claimRewardParams.r,
            claimRewardParams.s
        );

        if (!Registry(registry).checkIsSigner(signer)) {
            revert CommonError.NotSigner();
        }
    }

    function _checkSoupSig(
        IRebornDefinition.SoupParams calldata soupParams,
        uint256 nonce,
        address registry
    ) public view {
        if (block.timestamp >= soupParams.deadline) {
            revert CommonError.SignatureExpired();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                PortalLib._SOUPPARAMS_TYPEHASH,
                msg.sender,
                soupParams.soupPrice,
                nonce,
                soupParams.charTokenId,
                soupParams.deadline
            )
        );

        bytes32 hash = ECDSAUpgradeable.toTypedDataHash(
            _altarDomainSeparatorV4(),
            structHash
        );

        address signer = ECDSAUpgradeable.recover(
            hash,
            soupParams.v,
            soupParams.r,
            soupParams.s
        );

        if (!Registry(registry).checkIsSigner(signer)) {
            revert CommonError.NotSigner();
        }
    }
}

