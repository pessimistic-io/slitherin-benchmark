// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC721.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./Initializable.sol";

import "./VRF.sol";
import "./AccessControl.sol";
import "./Storage.sol";
import "./Balance.sol";
import "./ILootBoxStorage.sol";
import "./Prize.sol";
import "./Price.sol";
import "./Nft.sol";
import "./Jackpot.sol";
import "./Sign.sol";
import "./LootBox.sol";

contract LootBox is ILootBoxStorage, Storage, AccessControl, Nft, Prize, Price, Sign, VRF, Jackpot, IERC721Receiver, Balance {
    /**
     * @dev There is not fund to claim.
     */
    error NoFundsAvailable(address token, address pool);

    /**
     * @dev Contract wasn't properly initialized.
     * @param version required storage version.
     */
    error NotInitialized(uint8 version);

    /**
     * @dev Out of range.
     */
    error OutOfRange(string name, uint got, uint min, uint max);

    /**
     * @dev Wrong owner.
     */
    error WrongOwner(uint tokenId, address got, address owner);

    /**
     * @dev The action is called out of scope.
     */
    error OutOfScope(bool tooEarly, bool tooLate, bool maxSupplyReached);

    error NotEnoughErc20(address token, uint amount, address pool);

    /**
     * @dev Loot boxes are revealed.
     */
    event LootBoxRevealed(address indexed buyer, uint emptyCount, uint[] rarityCounts);
    /**
     * @dev NFT prize was won by the user.
     */
    event NftPrizeClaimed(uint indexed lootBoxId, uint indexed tokenId, address collection, address user, uint chainId);
    /**
     * @dev ERC20 prize was claimed by the user.
     */
    event Erc20PrizeClaimed(uint indexed lootBoxId, uint amount, address tokenContract, address user, uint chainId);

    uint8 constant public STORAGE_VERSION = 1;

    using TransferUtil for address;
    using ProbabilityLib for Probability;
    using IdTypeLib for IdType;
    using IdTypeLib for uint;
    using Random for Random.Seed;
    using StateTypeLib for StateType;
    using StateTypeLib for uint;

    modifier onlyInitialized() {
        if (_getInitializedVersion() != STORAGE_VERSION) {
            revert NotInitialized(STORAGE_VERSION);
        }
        _;
    }

    modifier onlyInScope(uint addingCount) {
        Scope storage scope = _scope();
        uint64 supply = _totalSupplyWithBoost() + uint64(addingCount);
        if (block.timestamp < scope.begin
            || block.timestamp >= scope.end
            || supply > scope.maxSupply) {
            revert OutOfScope(block.timestamp < scope.begin, block.timestamp >= scope.end, supply > scope.maxSupply);
        }
        _;
    }

    modifier onlyOutOfScope() {
        Scope storage scope = _scope();
        uint64 supply = _totalSupplyWithBoost();
        if (scope.alwaysBurn == 0 && block.timestamp < scope.end && supply < scope.maxSupply) {
            revert OutOfScope(block.timestamp < scope.end, false, supply < scope.maxSupply);
        }
        _;
    }

    function init(string memory name_, string memory symbol_, string memory baseUri_, uint64 maxSupply, uint32 begin, uint32 end, address signer) initializer public virtual override(Storage) {
        // in this case tx.origin is account who has access to proxy admin contract.
        _setupRole(ADMIN_ROLE, tx.origin);
        _setRoleAdmin(PRIZE_MANAGER_ROLE, ADMIN_ROLE);
        _grantRole(PRIZE_MANAGER_ROLE, tx.origin);
        if (maxSupply == 0) {
            maxSupply = type(uint64).max;
        }
        if (end == 0) {
            end = type(uint32).max;
        }
        if (begin >= end) {
            revert OutOfRange("begin", begin, 0, end);
        }
        Storage.init(name_, symbol_, baseUri_, maxSupply, begin, end, signer);
    }

    /**
     * @dev By a specified amount of LootBoxes for the specified tokens.
     */
    function buy(address token, uint count, uint16 boost) public {
        // @notice there is no modifiers only because they exists in the underlying method
        //          if you change the underlying method you have to add modifiers
        buyFor(_msgSender(), token, count, boost);
    }

    /**
     * @dev By a specified amount of LootBoxes for the specified tokens.
     */
    function buyFor(address user, address token, uint count, uint boost) public onlyInitialized onlyInScope(count * boost) {
        if (boost < MIN_NFT_BOOST || boost > MAX_NFT_BOOST) {
            revert OutOfRange("boost", boost, MIN_NFT_BOOST, MAX_NFT_BOOST);
        }
        if (count < MIN_BUY_COUNT || count > MAX_BUY_COUNT) {
            revert OutOfRange("count", count, MIN_BUY_COUNT, MAX_BUY_COUNT);
        }

        address payer = _msgSender();
        uint totalValue = _debit(token, payer, address(this), count * boost);
        if (boost > 1) {
            _addBoostAdding(uint32(count * boost - count));
        }

        uint jackpotAdd = _config().jackpotPriceShare.mul(totalValue);
        _addJackpot(token, int(jackpotAdd));

        IdType id = _nextTokenId(count);
        mintFor(user, count, uint16(boost), id);

        _requestBuyRandom(id, uint16(count));
    }

    function checkSignature(
        address user,
        uint64 externalId,
        uint64 expiredAt,
        Signature calldata signature) public view onlyInitialized returns (bool) {
        if (_getUsed(externalId)) {
            revert ExternalIdAlreadyUsed(externalId);
        }

        _verifySignature(address(this), user, externalId, expiredAt, signature);
        return true;
    }

    function acquireFree(
        address user,
        uint64 externalId,
        uint64 expiredAt,
        Signature calldata signature
    ) public onlyInScope(1) onlyInitialized {

        // check if this external id was used and mark it as used
        if (_getUsedAndSet(externalId)) {
            revert ExternalIdAlreadyUsed(externalId);
        }

        // verify signature
        _verifySignature(address(this), _msgSender(), externalId, expiredAt, signature);

        // mint new NFT
        uint16 count = 1;
        IdType id = _nextTokenId(count);
        mintFor(user, count, MIN_NFT_BOOST, id);

        // request random
        _requestBuyRandom(id, count);
    }

    /**
     * @dev Burn a token in exchange for a prize is chosen by random.
     */
    function burnForRandomPrize(uint rarity) public onlyInitialized onlyOutOfScope {
        if (rarity >= RARITIES) {
            revert OutOfRange("rarity", rarity, 0, RARITIES - 1);
        }

        // check claim counter
//        uint32 claimRequestsCount = _counters().claimRequestCounter;
        uint32 prizesCount = _rarity(rarity).count;
        if (prizesCount == 0) {
            burnForErc20Prize(rarity);
            return;
        }

        // lock box
        IdType lockedId = _lockFirst(_msgSender(), rarity);

//        _increaseClaimRequestCounter(1);
        _requestClaimRandom(lockedId);
    }

    /**
     * @dev Burn a token in exchange for a ERC20 prize.
     */
    function burnForErc20Prize(uint rarity) public onlyInitialized onlyOutOfScope {
        if (rarity >= RARITIES) {
            revert OutOfRange("rarity", rarity, 0, RARITIES - 1);
        }

        IdType id = _burnByRarity(_msgSender(), rarity);
        _decLootBoxCount(rarity);
        (bool result, uint amount, address token, uint32 chainId) =
                        _tryClaimErc20Prize(address(this), rarity, _msgSender(), uint32(block.chainid));

        if (!result) {
            revert NotEnoughErc20(token, amount, address(this));
        }
        else {
            emit Erc20PrizeClaimed(id.toTokenId(), amount, token, _msgSender(), chainId);
        }
    }

    /**
     * @dev Burn empty tokens in exchange for a jackpot.
     */
    function burnForJackpot() public onlyInitialized {
        _burnEmptyMultiple(_msgSender(), 3);
        _addEmptyCounter(-3);
        _claimJackpot(address(this), _msgSender());
    }

    //********* Utilities

    function _randomBuyResponseHandler(IdType firstId, uint16 count, Random.Seed memory random) internal override {
        uint emptyCount = 0;
        uint[] memory rarityCounts = new uint[](RARITIES);

        // get first owner to be sure that the rest are the same!
        // to avoid overriding nfts belonging to other
        address owner = _nft(firstId).owner;
        for (uint i = 0; i < count; i ++) {
            IdType id = firstId.next(i);
            NFTDef storage nft = _nft(id);
            uint16 boost = nft.boost;
            if (owner != nft.owner) {
                revert WrongOwner(id.toTokenId(), owner, nft.owner);
            }
            // determine rarity
            (bool rare, uint rarity) = _lookupRarity(random.get16(), boost);
            if (rare) {
                rarityCounts[rarity] ++;
                _markAsRare(id, rarity, random.get32());
            }
            else {
                _markAsEmpty(id, random.get32());
                emptyCount ++;
            }

        }

        for (uint i = 0; i < RARITIES; i ++) {
            uint32 counter = uint32(rarityCounts[i]);
            if (counter == 0) {
                continue;
            }

            _addLootBoxCount(i, counter);
        }

        _addEmptyCounter(int32(uint32(emptyCount)));

        emit LootBoxRevealed(owner, emptyCount, rarityCounts);
    }

    function _randomClaimResponseHandler(IdType id, Random.Seed memory random) internal override {
//        _decreaseClaimRequestCounter(1);
        uint32 thisChainId = uint32(block.chainid);
        NFTDef storage nft = _nft(id);
        if (!nft.state.isRare()) {
            revert WrongNftState(id.toTokenId(), uint(0).toState(), nft.state);
        }

        uint rarity = nft.state.toRarity();
        // check rarity pool size
        RarityDef storage rarityDef = _rarity(rarity);
        uint32 poolSize = rarityDef.count;
        bool winNft = false;

        // case 1: we have prizes
        if (poolSize > 0) {
            (bool nftResult, uint prizeTokenId, address collection, uint32 nftChainId) =
                            _tryPlayNftPrize(rarity, nft.owner, random, thisChainId);
            if (nftResult) {
                winNft = true;
                emit NftPrizeClaimed(id.toTokenId(), prizeTokenId, collection, nft.owner, nftChainId);
            }
        }

        // case 2: we do not have prizes or the chance is weak
        if (poolSize == 0 || !winNft) {
            (bool erc20result, uint prizeAmount, address token, uint32 erc20chainId) =
                            _tryClaimErc20Prize(address(this), rarity, nft.owner, thisChainId);

            // special case: no ERC20 tokens
            if (!erc20result) {
                _unlockAndReturn(id, nft);
                return;
            }
            emit Erc20PrizeClaimed(id.toTokenId(), prizeAmount, token, nft.owner, erc20chainId);
        }

        _burnLocked(nft.owner, id, nft);
        _decLootBoxCount(rarity);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, Nft) returns (bool) {
        return AccessControl.supportsInterface(interfaceId) || Nft.supportsInterface(interfaceId);
    }

    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    //*************** Public view functions

    function mintFor(address to, uint toMintCount, uint16 boost, IdType firstId) private {
        for (uint i = 0; i < toMintCount; i ++) {
            IdType nextId = firstId.next(i);
            _safeMint(to, nextId, boost);
        }
    }
}

