// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC721Upgradeable} from "./ERC721Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {UUPSUpgradeable} from "./utils_UUPSUpgradeable.sol";
import {BitMapsUpgradeable} from "./BitMapsUpgradeable.sol";
import {AddressUpgradeable} from "./utils_AddressUpgradeable.sol";
import {AutomationCompatible} from "./AutomationCompatible.sol";
import {SafeOwnableUpgradeable} from "./utils_SafeOwnableUpgradeable.sol";
import {IRebornPortal} from "./IRebornPortal.sol";
import {IBurnPool} from "./IBurnPool.sol";
import {RebornPortalStorage} from "./RebornPortalStorage.sol";
import {RBT} from "./RBT.sol";
import {RewardVault} from "./RewardVault.sol";
import {Renderer} from "./Renderer.sol";
import {CommonError} from "./CommonError.sol";
import {PortalLib} from "./PortalLib.sol";
import {IPiggyBank} from "./IPiggyBank.sol";
import {PiggyBank} from "./PiggyBank.sol";
import {AirdropVault} from "./AirdropVault.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {Registry} from "./Registry.sol";
import {DegenShovel} from "./DegenShovel.sol";
import {BlockNumberReader} from "./BlockNumberReader.sol";

// for storage compatible
abstract contract StorageCompat is RebornPortalStorage {

}

contract RebornPortal is
    IRebornPortal,
    SafeOwnableUpgradeable,
    UUPSUpgradeable,
    RebornPortalStorage,
    ERC721Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    StorageCompat,
    AutomationCompatible
{
    using BitMapsUpgradeable for BitMapsUpgradeable.BitMap;
    using AddressUpgradeable for address payable;

    /**
     * @dev initialize function
     * @param owner_ owner address
     * @param name_ ERC712 name
     * @param symbol_ ERC721 symbol
     */
    function initialize(
        address owner_,
        string memory name_,
        string memory symbol_,
        Registry registry_
    ) public initializer {
        if (owner_ == address(0) || address(registry_) == address(0)) {
            revert CommonError.ZeroAddressSet();
        }
        _registry = registry_;
        __Ownable_init(owner_);
        __ERC721_init(name_, symbol_);
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @inheritdoc IRebornPortal
     */
    function incarnate(
        InnateParams calldata innate,
        ReferParams calldata referParams,
        SoupParams calldata soupParams
    )
        external
        payable
        override
        whenNotStopped
        nonReentrant
        checkIncarnationCount
    {
        _refer(referParams);
        _incarnate(innate, soupParams);
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function incarnate(
        InnateParams calldata innate,
        ReferParams calldata referParams,
        SoupParams calldata soupParams,
        PermitParams calldata permitParams
    )
        external
        payable
        override
        whenNotStopped
        nonReentrant
        checkIncarnationCount
    {
        _refer(referParams);
        _permit(permitParams);
        _incarnate(innate, soupParams);
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function engrave(
        EngraveParams calldata engraveParams
    ) external override onlySigner {
        if (_seeds.get(uint256(engraveParams.seed))) {
            revert SameSeed();
        }
        _seeds.set(uint256(engraveParams.seed));

        address creator = details[engraveParams.tokenId].creator;

        details[engraveParams.tokenId] = LifeDetail(
            engraveParams.seed,
            creator,
            uint96(engraveParams.reward),
            uint96(engraveParams.rebornCost),
            uint16(engraveParams.age),
            uint16(++rounds[creator]),
            uint64(engraveParams.score),
            uint48(engraveParams.nativeCost / 10 ** 12),
            engraveParams.creatorName
        );

        uint256 startTokenId;
        // mint shovel
        if (engraveParams.shovelAmount > 0) {
            startTokenId = _registry.getShovel().mint(
                creator,
                engraveParams.shovelAmount
            );
        }

        // record reward for incarnation owner
        _rewardToClaim[creator][RewardToClaimType.EngraveDegen]
            .totalReward += engraveParams.reward;

        // record reward for referrer
        _rewardDegenRewardToRefs(creator, engraveParams.reward);

        // recover AP
        _recoverAP(engraveParams.charTokenId, engraveParams.recoveredAP);

        emit Engrave(
            engraveParams.seed,
            creator,
            engraveParams.tokenId,
            engraveParams.score,
            engraveParams.reward,
            engraveParams.shovelAmount,
            startTokenId,
            engraveParams.charTokenId,
            engraveParams.recoveredAP
        );
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function baptise(
        address user,
        uint256 amount,
        uint256 baptiseType
    ) external override onlySigner {
        vault.reward(user, amount);

        emit Baptise(user, amount, baptiseType);
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function infuse(
        uint256 tokenId,
        uint256 amount,
        TributeDirection tributeDirection
    ) external override whenNotStopped {
        _infuse(tokenId, amount, tributeDirection);
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function infuse(
        uint256 tokenId,
        uint256 amount,
        TributeDirection tributeDirection,
        PermitParams calldata permitParams
    ) external override whenNotStopped {
        _permit(permitParams);
        _infuse(tokenId, amount, tributeDirection);
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function switchPool(
        uint256 fromTokenId,
        uint256 toTokenId,
        uint256 amount,
        TributeDirection fromDirection,
        TributeDirection toDirection
    ) external override whenNotStopped {
        uint256 reStakeAmount = (amount * 95) / 100;

        emit SwitchPool(
            msg.sender,
            fromTokenId,
            toTokenId,
            amount,
            reStakeAmount,
            fromDirection,
            toDirection
        );
    }

    function exhume(
        ExhumeParams calldata exhumeParams
    ) external payable whenNotPaused {
        _exhume(exhumeParams);
    }

    function exhume(
        ExhumeParams calldata exhumeParams,
        PermitParams calldata permitParams
    ) external payable whenNotPaused {
        _permit(permitParams);
        _exhume(exhumeParams);
    }

    function claimReward(
        RewardToClaimType t
    ) external override whenNotPaused nonReentrant {
        uint256 remainingAmount = _rewardToClaim[msg.sender][t].totalReward -
            _rewardToClaim[msg.sender][t].rewardDebt;

        if (remainingAmount == 0) {
            revert NoRemainingReward();
        }

        _rewardToClaim[msg.sender][t].rewardDebt = _rewardToClaim[msg.sender][t]
            .totalReward;

        // if t is even, native reward
        if (uint8(t) % 2 == 0) {
            payable(msg.sender).sendValue(remainingAmount);
        } else {
            // t is odd, degen reward
            vault.reward(msg.sender, remainingAmount);
        }

        emit ClaimReward(msg.sender, t, remainingAmount);
    }

    function claimDegenReward(
        ClaimRewardParams calldata claimRewardParams
    ) external override {
        address user = claimRewardParams.user;
        uint256 nonce = ++_claimRewardNonce[user];

        PortalLib._checkClaimRewardSig(
            claimRewardParams,
            nonce,
            address(_registry)
        );

        vault.reward(user, claimRewardParams.amount);

        emit ClaimDegenReward(
            user,
            nonce,
            claimRewardParams.amount,
            claimRewardParams.t,
            claimRewardParams.r,
            claimRewardParams.s,
            claimRewardParams.v
        );
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function claimNativeDrops(
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external override nonReentrant whenNotPaused {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(msg.sender, totalAmount)))
        );

        bool valid = MerkleProof.verify(merkleProof, _dropNativeRoot, leaf);

        if (!valid) {
            revert InvalidProof();
        }

        uint256 remainingNativeAmount = totalAmount -
            _airdropDebt[msg.sender].nativeDebt;

        if (remainingNativeAmount == 0) {
            revert NoRemainingReward();
        }

        _airdropDebt[msg.sender].nativeDebt = uint128(totalAmount);

        // transfer from portal directly, so the remaining native in airdrop vault will become a part of jackpot
        payable(msg.sender).sendValue(remainingNativeAmount);

        emit ClaimNativeAirdrop(remainingNativeAmount);
    }

    /**
     * @inheritdoc IRebornPortal
     */
    function claimDegenDrops(
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external override whenNotPaused {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(msg.sender, totalAmount)))
        );

        bool valid = MerkleProof.verify(merkleProof, _dropDegenRoot, leaf);

        if (!valid) {
            revert InvalidProof();
        }

        uint256 remainingDegenAmount = totalAmount -
            _airdropDebt[msg.sender].degenDebt;

        if (remainingDegenAmount == 0) {
            revert NoRemainingReward();
        }

        _airdropDebt[msg.sender].degenDebt = uint128(totalAmount);

        airdropVault.rewardDegen(msg.sender, remainingDegenAmount);

        emit ClaimDegenAirdrop(remainingDegenAmount);
    }

    /**
     * @dev Upkeep perform of chainlink automation
     */
    function performUpkeep(
        bytes calldata performData
    ) external override whenNotStopped {}

    /**
     * @inheritdoc IRebornPortal
     */
    function toNextSeason() external onlyOwner {
        _getPiggyBank().stop(_season);

        unchecked {
            _season++;
        }

        // update piggyBank
        _getPiggyBank().initializeSeason(
            _season,
            uint32(block.timestamp),
            0.1 ether
        );

        // pause the contract
        _pause();

        emit NewSeason(_season);
    }

    /**
     * @dev manually set season, for convenient
     * @param season the season to set
     */
    function setSeason(uint256 season) public onlyOwner {
        _season = season;
        emit NewSeason(_season);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unPause() external onlyOwner {
        _unpause();
    }

    function setCharProperty(
        uint256[] calldata tokenIds,
        PortalLib.CharacterParams[] calldata charParams
    ) external onlySigner {
        uint256 tokenIdLength = tokenIds.length;
        uint256 charParamsLength = charParams.length;
        if (tokenIdLength != charParamsLength) {
            revert CommonError.InvalidParams();
        }
        for (uint256 i = 0; i < tokenIdLength; ) {
            uint256 tokenId = tokenIds[i];
            PortalLib.CharacterParams memory charParam = charParams[i];
            PortalLib.CharacterProperty
                storage charProperty = _characterProperties[tokenId];

            charProperty.maxAP = uint8(charParam.maxAP);
            charProperty.restoreTimePerAP = uint24(charParam.restoreTimePerAP);

            // restore all AP immediately when upgrade
            charProperty.currentAP = uint8(charParam.maxAP);

            charProperty.level = uint8(charParam.level);

            unchecked {
                i++;
            }
        }
    }

    function setNativeDropRoot(
        bytes32 nativeDropRoot,
        uint256 timestamp
    ) external onlySigner {
        _dropNativeRoot = nativeDropRoot;

        emit NativeDropRootSet(nativeDropRoot, timestamp);
    }

    function setDegenDropRoot(
        bytes32 degenDropRoot,
        uint256 timestamp
    ) external onlySigner {
        _dropDegenRoot = degenDropRoot;

        emit DegenDropRootSet(degenDropRoot, timestamp);
    }

    /**
     * @notice mul 100 when set. eg: 8% -> 800 18%-> 1800
     * @dev set percentage of referrer reward
     * @param rewardType 0: incarnate reward 1: engrave reward
     */
    function setReferrerRewardFee(
        uint16 refL1Fee,
        uint16 refL2Fee,
        PortalLib.RewardType rewardType
    ) external onlyOwner {
        if (rewardType == PortalLib.RewardType.NativeToken) {
            rewardFees.incarnateRef1Fee = refL1Fee;
            rewardFees.incarnateRef2Fee = refL2Fee;
        } else if (rewardType == PortalLib.RewardType.RebornToken) {
            rewardFees.vaultRef1Fee = refL1Fee;
            rewardFees.vaultRef2Fee = refL2Fee;
        }
    }

    /**
     * @dev set vault
     * @param vault_ new vault address
     */
    function setVault(RewardVault vault_) external onlyOwner {
        vault = vault_;
        emit VaultSet(address(vault_));
    }

    function setRegistry(address r) external onlyOwner {
        _registry = Registry(r);
    }

    /**
     * @dev set airdrop vault
     * @param vault_ new airdrop vault address
     */
    function setAirdropVault(AirdropVault vault_) external onlyOwner {
        airdropVault = vault_;
        emit AirdropVaultSet(address(vault_));
    }

    /**
     * @dev set incarnation limit
     */
    function setIncarnationLimit(uint256 limit) external onlyOwner {
        _incarnateCountLimit = limit;
        emit NewIncarnationLimit(limit);
    }

    /**
     * @dev withdraw token from vault
     * @param to the address which owner withdraw token to
     */
    function withdrawVault(address to) external onlyOwner {
        vault.withdrawEmergency(to);
    }

    /**
     * @dev withdraw token from airdrop vault
     * @param to the address which owner withdraw token to
     */
    function withdrawAirdropVault(address to) external onlyOwner {
        airdropVault.withdrawEmergency(to);
    }

    /**
     * @dev burn $REBORN from burn pool
     * @param amount burn from burn pool
     */
    function burnFromBurnPool(uint256 amount) external onlyOwner {
        IBurnPool(burnPool).burn(amount);
    }

    /**
     * @dev forging with permit
     */
    function forging(
        uint256 tokenId,
        uint256 toLevel,
        PermitParams calldata permitParams
    ) external {
        _permit(permitParams);
        _forging(tokenId, toLevel);
    }

    function forging(uint256 tokenId, uint256 toLevel) external {
        _forging(tokenId, toLevel);
    }

    function _forging(uint256 tokenId, uint256 toLevel) internal {
        uint256 currentLevel = _characterProperties[tokenId].level;
        if (currentLevel >= toLevel) {
            revert CommonError.InvalidParams();
        }
        uint256 requiredAmount;
        for (uint256 i = currentLevel; i < toLevel; ) {
            uint256 thisLevelAmount = _forgeRequiredMaterials[i];

            if (thisLevelAmount == 0) {
                revert CommonError.InvalidParams();
            }

            unchecked {
                requiredAmount += thisLevelAmount;
                i++;
            }
        }

        _getDegen().transferFrom(msg.sender, burnPool, requiredAmount);

        emit ForgedTo(tokenId, toLevel, requiredAmount);
    }

    function initializeSeason(uint256 target) external payable onlyOwner {
        _getPiggyBank().initializeSeason{value: msg.value}(
            _season,
            BlockNumberReader.getBlockNumber(),
            target
        );
    }

    function setForgingRequiredAmount(
        uint256[] memory levels,
        uint256[] memory amounts
    ) external onlyOwner {
        uint256 levelsLength = levels.length;
        uint256 amountsLength = amounts.length;

        if (levelsLength != amountsLength) {
            revert CommonError.InvalidParams();
        }

        for (uint256 i = 0; i < levelsLength; ) {
            _forgeRequiredMaterials[levels[i]] = amounts[i];
            unchecked {
                i++;
            }
        }
    }

    // set burnPool address for pre burn $REBORN
    function setBurnPool(address burnPool_) external onlyOwner {
        if (burnPool_ == address(0)) {
            revert CommonError.ZeroAddressSet();
        }
        burnPool = burnPool_;
    }

    function setPiggyBankFee(uint256 piggyBankFee_) external onlyOwner {
        piggyBankFee = piggyBankFee_;

        emit SetNewPiggyBankFee(piggyBankFee_);
    }

    /**
     * @dev withdraw native token for reward distribution
     * @dev amount how much to withdraw
     */
    function withdrawNativeToken(
        address to,
        uint256 amount
    ) external onlyOwner {
        payable(to).sendValue(amount);
    }

    /**
     * @dev checkUpkeep for chainlink automation
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {}

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        return Renderer.renderByTokenId(details, tokenId);
    }

    /**
     * @dev run erc20 permit to approve
     */
    function _permit(PermitParams calldata permitParams) internal {
        _getDegen().permit(
            msg.sender,
            address(this),
            permitParams.amount,
            permitParams.deadline,
            permitParams.v,
            permitParams.r,
            permitParams.s
        );
    }

    function _infuse(
        uint256 tokenId,
        uint256 amount,
        TributeDirection tributeDirection
    ) internal {
        // it's not necessary to check the whether the address of burnPool is zero
        // as function transferFrom does not allow transfer to zero address by default
        _getDegen().transferFrom(msg.sender, burnPool, amount);

        emit Infuse(msg.sender, tokenId, amount, tributeDirection);
    }

    /**
     * @dev record referrer relationship
     */
    function _refer(ReferParams calldata referParams) internal {
        // parent refer msg.sender
        if (
            referrals[msg.sender] == address(0) &&
            referParams.parent != address(0) &&
            referParams.parent != msg.sender
        ) {
            referrals[msg.sender] = referParams.parent;
            emit Refer(msg.sender, referParams.parent);
        }
        // grandParent refer parent
        if (
            referrals[referParams.parent] == address(0) &&
            referParams.grandParent != address(0) &&
            referParams.parent != referParams.grandParent
        ) {
            referrals[referParams.parent] = referParams.grandParent;
            emit Refer(referParams.parent, referParams.grandParent);
        }
    }

    /**
     * @dev implementation of incarnate
     */
    function _incarnate(
        InnateParams calldata innate,
        SoupParams calldata soupParams
    ) internal {
        // use soup
        PortalLib._useSoupParam(
            soupParams,
            getIncarnateCount(_season, msg.sender),
            _characterProperties,
            address(_registry)
        );

        uint256 nativeFee = soupParams.soupPrice +
            innate.talentNativePrice +
            innate.propertyNativePrice;

        uint256 degenFee = innate.talentDegenPrice + innate.propertyDegenPrice;

        // both larger and smaller are invalid
        if (msg.value != nativeFee) {
            revert CommonError.InvalidParams();
        }

        // reward referrers
        uint256 referNativeAmount = PortalLib._sendNativeRewardToRefs(
            referrals,
            rewardFees,
            _rewardToClaim,
            msg.sender,
            nativeFee
        );

        uint256 netNativeAmount;
        unchecked {
            netNativeAmount = nativeFee - referNativeAmount;
        }

        uint256 piggyBankAmount = (netNativeAmount * piggyBankFee) /
            PortalLib.PERCENTAGE_BASE;

        // more check
        // piggy bank amount should be less than net native amount
        if (piggyBankAmount > netNativeAmount) {
            revert CommonError.InvalidParams();
        }

        // x% to piggyBank
        _getPiggyBank().deposit{value: piggyBankAmount}(
            _season,
            msg.sender,
            nativeFee
        );

        // degen to burn pool
        _getDegen().transferFrom(msg.sender, burnPool, degenFee);

        // mint erc721
        uint256 tokenId;
        unchecked {
            // tokenId auto increment
            tokenId = ++idx + (block.chainid * 1e18);
        }
        _safeMint(msg.sender, tokenId);
        // set creator
        details[tokenId].creator = msg.sender;

        emit Incarnate(
            msg.sender,
            tokenId,
            soupParams.charTokenId,
            innate.talentNativePrice,
            innate.talentDegenPrice,
            innate.propertyNativePrice,
            innate.propertyDegenPrice,
            soupParams.soupPrice
        );
    }

    function _exhume(ExhumeParams calldata exhumeParams) internal nonReentrant {
        uint256 nativeCost = exhumeParams.nativeCost;
        uint256 degenCost = exhumeParams.degenCost;
        address exhumee = exhumeParams.exhumee;
        uint256 tombstoneTokenId = exhumeParams.tokenId;
        address creator = details[tombstoneTokenId].creator;

        if (details[tombstoneTokenId].score == 0) {
            revert CommonError.TombstoneNotEngraved();
        }

        uint256 currentCount;
        unchecked {
            currentCount = ++_exhumeCount[tombstoneTokenId];
        }

        // check signature and param
        PortalLib._checkExhumeSig(
            exhumeParams,
            currentCount,
            address(_registry)
        );

        // check tombstone tokenId owner
        if (ownerOf(tombstoneTokenId) != exhumee) {
            revert CommonError.ExhumeeNotTombStoneOwner();
        }

        // check shovel and burn
        if (exhumeParams.shovelTokenId != 0) {
            if (
                _getShovel().ownerOf(exhumeParams.shovelTokenId) != msg.sender
            ) {
                revert CommonError.NotShovelOwner();
            }
            _getShovel().burn(exhumeParams.shovelTokenId);
        }

        // check native token
        // minus directly as if msg.value is not enough, it will overflow
        uint256 extraAmount = msg.value - nativeCost;
        payable(msg.sender).sendValue(extraAmount);

        // distribute native and degen token
        if (currentCount == 1) {
            // 80% native to last owner
            payable(exhumee).sendValue((nativeCost * 80) / 100);
            // 10%  to creator
            payable(exhumee).sendValue((nativeCost * 10) / 100);
        } else {
            // 85% native to last owner
            payable(exhumee).sendValue((nativeCost * 85) / 100);
            // 5% native to creator
            payable(creator).sendValue((nativeCost * 5) / 100);
        }

        // 70% degen burn
        _getDegen().transferFrom(msg.sender, burnPool, (degenCost * 70) / 100);

        // 25% degen to last owner
        _getDegen().transferFrom(msg.sender, exhumee, (degenCost * 25) / 100);

        // 5% degen to creator
        _getDegen().transferFrom(msg.sender, creator, (degenCost * 5) / 100);

        // transfer nft ownership
        // it will check old ownership again
        _transfer(exhumee, msg.sender, tombstoneTokenId);

        // emit event
        emit Exhume(
            msg.sender,
            exhumee,
            tombstoneTokenId,
            exhumeParams.shovelTokenId,
            currentCount,
            nativeCost,
            degenCost,
            (nativeCost * 1) / 10
        );
    }

    function _recoverAP(uint256 charTokenId, uint256 recoveredAP) internal {
        // recover char AP
        if (charTokenId != 0) {
            uint256 increasedAP = _characterProperties[charTokenId].currentAP +
                recoveredAP;
            if (increasedAP > _characterProperties[charTokenId].maxAP) {
                _characterProperties[charTokenId]
                    .currentAP = _characterProperties[charTokenId].maxAP;
            } else {
                _characterProperties[charTokenId].currentAP = uint8(
                    increasedAP
                );
            }
        }
    }

    function _rewardDegenRewardToRefs(
        address creator,
        uint256 reward
    ) internal {
        // record reward for referrer
        PortalLib._rewardDegenRewardToRefs(
            referrals,
            rewardFees,
            _rewardToClaim,
            creator,
            reward
        );
    }

    /**
     * @dev returns referrer and referrer reward
     * @return ref1 level1 of referrer. direct referrer
     * @return ref1Reward level 1 referrer reward
     * @return ref2 level2 of referrer. referrer's referrer
     * @return ref2Reward level 2 referrer reward
     */
    function calculateReferReward(
        address account,
        uint256 amount,
        PortalLib.RewardType rewardType
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
        return
            PortalLib._calculateReferReward(
                referrals,
                rewardFees,
                account,
                amount,
                rewardType
            );
    }

    function getIncarnateCount(
        uint256 season,
        address user
    ) public view returns (uint256) {
        return _incarnateCounts[season][user];
    }

    function getIncarnateLimit() public view returns (uint256) {
        return _incarnateCountLimit;
    }

    function getClaimDegenNonces(
        address user
    ) public view override returns (uint256) {
        return _claimRewardNonce[user];
    }

    /**
     * A -> B -> C: B: level1 A: level2
     * @dev referrer1: level1 of referrers referrer2: level2 of referrers
     */
    function getReferrers(
        address account
    ) public view returns (address referrer1, address referrer2) {
        referrer1 = referrals[account];
        referrer2 = referrals[referrer1];
    }

    function getAirdropDebt(
        address user
    ) public view returns (AirDropDebt memory) {
        return _airdropDebt[user];
    }

    function getRewardToClaim(
        address user,
        RewardToClaimType t
    ) public view returns (RewardStore memory) {
        return _rewardToClaim[user][t];
    }

    function readCharProperty(
        uint256 tokenId
    ) public view returns (PortalLib.CharacterProperty memory) {
        PortalLib.CharacterProperty memory charProperty = _characterProperties[
            tokenId
        ];

        PortalLib.CurrentAPReturn memory car = PortalLib._calculateCurrentAP(
            charProperty
        );

        charProperty.currentAP = uint8(car.currentAP);

        charProperty.lastTimeAPUpdate = uint32(car.lastAPUpdateTime);

        return charProperty;
    }

    function _checkIncarnationCount() internal {
        uint256 currentIncarnateCount = getIncarnateCount(_season, msg.sender);
        if (currentIncarnateCount >= _incarnateCountLimit) {
            revert IncarnationExceedLimit();
        }

        unchecked {
            _incarnateCounts[_season][msg.sender] = ++currentIncarnateCount;
        }
    }

    /**
     * @dev check signer implementation
     */
    function _checkSigner() internal view {
        if (!_registry.checkIsSigner(msg.sender)) {
            revert CommonError.NotSigner();
        }
    }

    function _checkStopped() internal view {
        if (_getPiggyBank().checkIsSeasonEnd(_season)) {
            revert SeasonAlreadyStopped();
        }

        if (paused()) {
            revert PauseablePaused();
        }
    }

    function _getPiggyBank() internal view returns (PiggyBank) {
        return _registry.getPiggyBank();
    }

    function _getDegen() internal view returns (RBT) {
        return _registry.getDegen();
    }

    function _getShovel() internal view returns (DegenShovel) {
        return _registry.getShovel();
    }

    modifier onlySigner() {
        _checkSigner();
        _;
    }

    /**
     * @dev check incarnation Count and auto increment if it meets
     */
    modifier checkIncarnationCount() {
        _checkIncarnationCount();
        _;
    }

    modifier whenNotStopped() {
        _checkStopped();
        _;
    }
}

