// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IERC721.sol";
import "./IERC20.sol";

import "./IPrizeStorage.sol";
import "./Utils.sol";
import "./Random.sol";


abstract contract Prize is IPrizeStorage {
    using ProbabilityLib for Probability;
    using ProbabilityLib for uint16;
    using TransferUtil for address;
    using Random for Random.Seed;
    using ProbabilityLib for Probability;

    error RarityLevelTooBig(uint level, uint maxLevel);
    error WrongRarityOrder(uint level, Probability current, Probability prev);
    error WrongTotalRaritiesProbability(Probability current, Probability expected);

    error NftNotAccessible(address collection, uint tokenId, address pool, address owner);
    error TooSmallBalance(address token, uint expected, uint actual);
    error NftAlreadyUsed(address collection, uint tokenId);
    error NftPrizeNotFound(address collection, uint tokenId);
    error NftPrizeNotAvailable(uint rarirty);
    error NoNftPrizeAvailable(uint rarity);
    error NoErc20PrizeAvailable(uint rarirty);
    error RarityByProbabilityNotFound(uint chance);
    error ArrayLengthOutOfRange(uint specified, uint min, uint max);

    /**
     * @dev Sets the specified probability at the specified rarity level.
     *      It reverts in case of wrong argument but doesn't check the order.
     */
    function _setRarity(uint level, uint16 probability) internal {
        if (level >= RARITIES) {
            revert RarityLevelTooBig(level, RARITIES - 1);
        }

        _rarity(level, probability.toProbability());
    }

    /**
     * @dev Checks rarity order. Revert if the order is wrong.
     */
    function _checkRaritiesOrder() internal view {
        Probability total = PROBABILITY_ZERO;
        Probability previous = PROBABILITY_ZERO;
        for (uint i = 0; i < RARITIES; i ++) {
            Probability probability = _rarity(i).probability;
            if (probability < previous) {
                revert WrongRarityOrder(i, probability, previous);
            }
            previous = probability;
            total = total.add(probability);
        }
        // there is no more total correction, the rest probability is a chance to win jackpot
//        if (total != PROBABILITY_MAX) {
//            revert WrongTotalRaritiesProbability(total, PROBABILITY_MAX);
//        }
    }

    function _checkNftAccessible(address pool, address collection, uint tokenId) internal view {
        address owner = IERC721(collection).ownerOf(tokenId);
        if (IERC721(collection).isApprovedForAll(owner, address(this))) {
            return;
        }
        if (IERC721(collection).ownerOf(tokenId) == address(this)) {
            return;
        }
        if (IERC721(collection).getApproved(tokenId) == address(this)) {
            return;
        }
        revert NftNotAccessible(collection, tokenId, pool, owner);
    }

    function _checkNftNotUsed(address collection, uint tokenId) internal view {
        if (_getPrizeIdByNft(collection, tokenId) > 0) {
            revert NftAlreadyUsed(collection, tokenId);
        }
    }

//    function _checkErc20(address pool, address token, uint amount) internal view {
//        if (IERC20(token).balanceOf(pool) <= amount) {
//            revert TooSmallBalance(token, amount, IERC20(token).balanceOf(pool));
//        }
//    }

    function _setErc20Prize(uint rarity, address token, uint amount, uint32 chainId) internal returns(uint32) {
        uint32 ercPrizeId = _getPrizeIdOffset(uint8(rarity));

        PrizeDef storage prizeDef = _prizes(ercPrizeId);
        prizeDef.token = token;
        prizeDef.value = amount;
        prizeDef.chainId = chainId;

        return ercPrizeId;
    }

    function _addNftPrizes(uint rarity, NftInfo[] memory nfts, address pool) internal {
        // TODO: add pool size check
        uint count = nfts.length;
        if (count == 0 || count > type(uint16).max) {
            revert ArrayLengthOutOfRange(count, 1, type(uint16).max);
        }
        RarityDef storage rarityDef = _rarity(rarity);

        // get first id
        uint32 firstId = rarityDef.count;
        if (firstId < MIN_PRIZE_INDEX) {
            firstId = MIN_PRIZE_INDEX;
        }
        firstId = _getPrizeIdOffset(uint8(rarity)) + firstId;

        // we move from left to right
        uint32 left = rarityDef.tail;

        for (uint32 i = 0; i < count; i ++) {
            uint32 id = firstId + i;

            // check if already used
            uint32 existingId = _getPrizeIdByNft(nfts[i].collection, nfts[i].tokenId);
            if (existingId != 0) {
                revert NftAlreadyUsed(nfts[i].collection, nfts[i].tokenId);
            }
            // mark as used
            _addPrizeIdByNft(nfts[i].collection, nfts[i].tokenId, id);

            // save payload
            PrizeDef storage prizeDef = _prizes(id);
            prizeDef.token = nfts[i].collection;
            prizeDef.value = nfts[i].tokenId;
            prizeDef.probability = nfts[i].probability;
            prizeDef.flags = PRIZE_NFT;
            prizeDef.chainId = nfts[i].chainId;

            // save list
            prizeDef.left = left;
            // next element or zero
            prizeDef.right = (i == count - 1 ? 0 : id + 1);
            left = id;
        }

        // connect to the existing list
        if (rarityDef.tail != 0) {
            PrizeDef storage prevPrize = _prizes(rarityDef.tail);
            prevPrize.right = firstId;
        }

        // update rarity def
        rarityDef.tail = left;
        rarityDef.count += uint32(count);
        if (rarityDef.head == 0) {
            rarityDef.head = firstId;
        }
    }

    function _removeNftPrize(uint rarity, address collection, uint tokenId) internal {
        uint32 id = _getPrizeIdByNft(collection, tokenId);
        if (id == 0) {
            revert NftPrizeNotFound(collection, tokenId);
        }

        RarityDef storage rarityDef = _rarity(rarity);
        PrizeDef storage prizeDef = _prizes(id);

        uint32 lastId = _getPrizeIdOffset(uint8(rarity)) + rarityDef.count;

        _removePrizeIdByNft(prizeDef.token, prizeDef.value);

        if (lastId > id) {
            PrizeDef storage lastPrizeDef = _prizes(lastId);
            _cloneParams(lastPrizeDef, prizeDef);
            _addPrizeIdByNft(lastPrizeDef.token, lastPrizeDef.value, id);
        }

        _delPrize(lastId);
        rarityDef.count --;
    }

    function _tryPlayNftPrize(
            uint rarity,
            address target,
            Random.Seed memory random,
            uint32 chainId) internal returns (bool, uint, address, uint32) {
        // get random prize
        uint32 poolSize = _rarity(rarity).count;
        uint32 prizeIndex = (random.get32() % poolSize) + MIN_PRIZE_INDEX;
        uint32 prizeId = _getPrizeIdOffset(rarity) + prizeIndex;
        PrizeDef storage prizeDef = _prizes(prizeId);

        // check if prize is played out
        if (!prizeDef.probability.isPlayedOut(random.get16(), 1)) {
            return (false, 0, address(0), 0);
        }

        // transfer prize
        address collection = prizeDef.token;
        uint tokenId = prizeDef.value;
        uint32 prizeChainId = prizeDef.chainId;

        _removeNftPrize(rarity, collection, tokenId);

        if (prizeChainId == chainId) {
            collection.erc721Transfer(target, tokenId);
        }

        return (true,  tokenId, collection, prizeChainId);
    }

    function _tryClaimErc20Prize(
            address pool,
            uint rarity,
            address target,
            uint32 chainId) internal returns (bool, uint, address, uint32) {
        uint32 id = _getPrizeIdOffset(rarity);

        PrizeDef storage prizeDef = _prizes(id);
        address token = prizeDef.token;
        uint amount = prizeDef.value;

        if (amount == 0) {
            revert NoErc20PrizeAvailable(rarity);
        }

        if (prizeDef.chainId == chainId) {
            uint balance = token.erc20BalanceOf(pool);
            if (balance < amount) {
                return (false, amount, token, 0);
            }

            token.erc20TransferFrom(pool, target, amount);
        }

        return (true, amount, token, prizeDef.chainId);
    }

    function _addLootBoxCount(uint rarity, uint32 count) internal {
        RarityDef storage rarityDef = _rarity(rarity);
        rarityDef.lbCounter += count;
    }

    function _decLootBoxCount(uint rarity) internal {
        RarityDef storage rarityDef = _rarity(rarity);
        rarityDef.lbCounter --;
    }

    function _lookupRarity(uint random, uint16 boost) internal view returns (bool, uint) {
        uint chance = random % PROBABILITY_DIVIDER;
        for (uint i = 0; i < RARITIES; i ++) {
            uint val = _rarity(i).probability.toUint16() * boost;
            if (chance < val) {
                return (true, i);
            }
            chance -= val;
        }
        return (false, 0);
    }

    function _cloneParams(PrizeDef storage fromPrize, PrizeDef storage toPrize) private {
        toPrize.token = fromPrize.token;
        toPrize.flags = fromPrize.flags;
        toPrize.right = fromPrize.right;
        toPrize.left = fromPrize.left;
        toPrize.value = fromPrize.value;
        toPrize.probability = fromPrize.probability;
    }

    function _getPrizeIdOffset(uint rarity) internal pure returns (uint32) {
        return uint32(rarity * RARITY_PRIZE_CAPACITY);
    }
}

