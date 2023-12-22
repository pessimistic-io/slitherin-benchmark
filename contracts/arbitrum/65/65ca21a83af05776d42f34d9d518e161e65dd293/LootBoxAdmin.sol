// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./Initializable.sol";
import "./Storage.sol";
import "./Utils.sol";
import "./Random.sol";
import "./Prize.sol";
import "./AccessControl.sol";
import "./Price.sol";
import "./VRF.sol";


contract LootBoxAdmin is Storage, AccessControl, Prize, Price, VRF {
    /**
     * @dev Rarities array has wrong length. It MUST be the same is RARITIES defined in the contract.
     */
    error WrongRaritiesLength(uint given, uint expected);

    /**
     * @dev There is not fund to claim.
     */
    error NoFundsAvailable(address token, address pool);

    /**
     * @dev Out of range.
     */
    error OutOfRange(string name, uint got, uint min, uint max);

    /**
     * @dev Method is not implemented in current implementation.
     */
    error NotImplemented();

    using TransferUtil for address;
    using ProbabilityLib for Probability;
    using IdTypeLib for IdType;
    using IdTypeLib for uint;
    using Random for Random.Seed;

    struct TokenInfo {
        address token;
        uint price;
        uint jackpot;
    }

    struct PrizeInfo {
        uint rarity;
        address erc20Token;
        uint erc20Amount;
        uint erc20Total;
        uint32 erc20ChainId;
        uint total;
        uint offset;
        NftInfo[] nfts;
    }

    struct State {
        uint maxSupply;
        uint startTimestamp;
        uint endTimestamp;
        uint totalSupply;
        uint[] prizeCounts;
        uint emptyCounter;
        uint[] lbCounters;
    }

    struct BalanceInfo {
        address owner;
        uint emptyCounter;
        uint firstEmptyTokenId;
        uint mysteryCounter;
        uint[] rarityCounters;
        uint[] firstTokenIds;
    }

    function probabilities() public view returns (uint16[] memory) {
        uint16[] memory result = new uint16[](RARITIES);
        for (uint i = 0; i < RARITIES; i ++) {
            result[i] = _rarity(i).probability.toUint16();
        }
        return result;
    }

    //*************** Public view functions

    /*
     * @dev Returns token price and jackpot amount.
     * @notice 0x0 token address means native token.
     */
    function getTokenInfo() public view returns (TokenInfo[] memory result) {
        uint count = _listJackpots().length;
        result = new TokenInfo[](count);
        for (uint i = 0; i < count; i ++) {
            address token = _listJackpots()[i];
            result[i].token = token;
            result[i].price = _price(token);
            result[i].jackpot = _jackpot(token);
        }
    }

    function getBalanceInfo(address owner) public view returns (BalanceInfo memory) {
        NFTCounter storage counters = _balances(owner);

        uint[] memory rarityCounters = new uint[](RARITIES);
        uint[] memory tokenIds = new uint[](RARITIES);
        for (uint i  = 0; i < RARITIES; i ++) {
            rarityCounters[i] = counters.rarityIdToCount[i];
            tokenIds[i] = counters.rarityIdToHead[i].toTokenId();
        }

        return BalanceInfo(
            owner,
            counters.emptyCount,
            counters.emptyHead.toTokenId(),
            counters.mysteryCount,
            rarityCounters,
            tokenIds
        );
    }

    function getPrizes(uint rarity, uint32 offset, uint32 limit) public view returns (PrizeInfo memory result) {
        if (rarity >= RARITIES) {
            revert OutOfRange("rarity", rarity, 0, RARITIES - 1);
        }
        result.rarity = rarity;
        uint32 thisChainId = uint32(block.chainid);

        RarityDef storage rarityDef = _rarity(rarity);

        PrizeDef storage ercPrize = _prizes(_getPrizeIdOffset(uint8(rarity)));
        if (ercPrize.value != 0) {
            result.erc20Token = ercPrize.token;
            result.erc20Amount = ercPrize.value;
            result.erc20ChainId = ercPrize.chainId;
            if (result.erc20ChainId == thisChainId) {
                result.erc20Total = ercPrize.token.erc20BalanceOf(address(this));
            }
        }

        result.total = rarityDef.count;

        if (offset > rarityDef.count) {
            limit = 0;
        }
        else if (limit > rarityDef.count - offset) {
            limit = rarityDef.count - offset;
        }

        if (limit == 0) {
            return result;
        }

        result.nfts = new NftInfo[](limit);

        uint32 head = rarityDef.head;
        uint index = 0;
        do {
            PrizeDef storage prize = _prizes(head);
            if (offset != 0) {
                offset --;
                head = prize.right;
                continue;
            }
            result.nfts[index].collection = prize.token;
            result.nfts[index].tokenId = prize.value;
            result.nfts[index].chainId = prize.chainId;

            index ++;
            head = prize.right;
        }
        while (head != 0 && index < limit);
    }

    function getState() public view returns (State memory) {
        uint[] memory rarityCounters = new uint[](RARITIES);
        uint[] memory lbCounts = new uint[](RARITIES);

        for (uint i = 0; i < RARITIES; i ++) {
            rarityCounters[i] = _rarity(i).count;
            lbCounts[i] = _rarity(i).lbCounter;
        }

        return State(
            _scope().maxSupply,
            _scope().begin,
            _scope().end,
            _counters().nextBoxId.toTokenId() - 1,
            rarityCounters,
            _counters().emptyCounter,
            lbCounts
        );
    }

    function _randomBuyResponseHandler(IdType, uint16, Random.Seed memory) internal override {
        revert NotImplemented();
    }

    function _randomClaimResponseHandler(IdType, Random.Seed memory) internal override {
        revert NotImplemented();
    }

    //*************** Admin functions

    function claimFunds(address token, address to) public onlyRole(ADMIN_ROLE) {
        address pool = address(this);
        uint total = token.erc20BalanceOf(pool);
        if (total == 0) {
            revert NoFundsAvailable(token, pool);
        }
        total -= _jackpot(token);
        if (total == 0) {
            revert NoFundsAvailable(token, pool);
        }
        token.erc20TransferFrom(pool, to, total);
    }

    function withdrawNft(address collection, uint tokenId, address to) public onlyRole(ADMIN_ROLE) {
        collection.erc721Transfer(to, tokenId);
    }

    function setPrice(address token, uint price) public onlyRole(ADMIN_ROLE) {
        _setPrice(token, price);
    }

    function getPrice(address token) public view returns (uint) {
        return _price(token);
    }

    function addNftPrizes(uint rarity, NftInfo[] memory infos) public onlyRole(PRIZE_MANAGER_ROLE) {
        _addNftPrizes(rarity, infos, address(this));
    }

    function removeNftPrize(uint rarity, address collection, uint tokenId) public onlyRole(ADMIN_ROLE) {
        _removeNftPrize(rarity, collection, tokenId);
    }

    function setErc20Prize(uint rarity, address token, uint amount, uint32 chainId) public onlyRole(PRIZE_MANAGER_ROLE) {
        if (rarity >= RARITIES) {
            revert OutOfRange("rarity", rarity, 0, RARITIES - 1);
        }
        _setErc20Prize(rarity, token, amount, chainId);
    }

    function setAllRarities(uint16[] calldata probabilities_) public onlyRole(PRIZE_MANAGER_ROLE) {
        if (probabilities_.length != RARITIES) {
            revert WrongRaritiesLength(probabilities_.length, RARITIES);
        }
        for (uint i = 0; i < RARITIES; i ++) {
            _setRarity(i, probabilities_[i]);
        }
        _checkRaritiesOrder();
    }

    function setJackpotParams(Probability jackpotShare, Probability jackpotPriceShare) public onlyRole(ADMIN_ROLE) {
        Config storage config = _config();
        config.jackpotPriceShare = jackpotPriceShare;
        config.jackpotShare = jackpotShare;
    }

    function setVRFParams(address vrfCoordinator, uint64 subscriptionId, uint32 callbackGasLimit, uint16 requestConfirmations, bytes32 keyHash) public onlyRole(ADMIN_ROLE) {
        Config storage config = _config();
        config.vrfCoordinator = vrfCoordinator;
        config.subscriptionId = subscriptionId;
        config.callbackGasLimit = callbackGasLimit;
        config.requestConfirmations = requestConfirmations;
        config.keyHash = keyHash;
    }

    function setSigner(address signerAddress) public onlyRole(ADMIN_ROLE) {
        _signer(signerAddress);
    }

    function setAlwaysBurn(bool alwaysBurn) public onlyRole(ADMIN_ROLE) {
        _scope().alwaysBurn = alwaysBurn ? 1 : 0;
    }

    function repeatRandomRequest(uint requestId) public onlyRole(ADMIN_ROLE) {
        _repeatRequest(requestId);
    }

    function requestRandomManually(uint tokenId, uint count, bool buy) public onlyRole(ADMIN_ROLE) {
        if (buy) {
            _requestBuyRandom(tokenId.toId(), uint16(count));
        }
        else {
            _requestClaimRandom(tokenId.toId());
        }
    }

    function debugNft(uint tokenId) public view returns (NFTDef memory) {
        return _nft(tokenId.toId());
    }
}

