// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./Initializable.sol";

import "./INftStorage.sol";
import "./IPrizeStorage.sol";
import "./IPriceStorage.sol";
import "./ILootBoxStorage.sol";
import "./IAccessControlStorage.sol";
import "./IConfigStorage.sol";
import "./IVRFStorage.sol";
import "./Uint16Maps.sol";
import "./IJackpotStorage.sol";
import "./ISignedNftStorage.sol";
import "./IBalanceStorage.sol";

contract Storage is Initializable, INftStorage, IPrizeStorage, IPriceStorage, IJackpotStorage, ILootBoxStorage, IAccessControlStorage, IConfigStorage, IVRFStorage, ISignedNftStorage, IBalanceStorage {
    using IdTypeLib for IdType;

    /// ERC721 storage
    // Token name
    string private name;

    // Token symbol
    string private symbol;

    string private baseUri;

    // Mapping from token ID to token definition
    mapping(IdType => NFTDef) private nfts;

    // Mapping owner address to rarities counts
    mapping(address => NFTCounter) private userToRaritiesCounters;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private operatorApprovals;

    /// IPrizeStorage
    // TODO: make it private, public only for debug
    mapping(uint => RarityDef) public rarities;
    // TODO: make it private, public only for debug
    mapping(uint32 => PrizeDef) public prizes;
    mapping(bytes32 => uint32) private uniquePrize;

    /// IPriceStorage
    mapping(address => uint) private prices;
    address[] private priceTokens;

    /// IAccessControlStorage
    mapping(bytes32 => RoleData) private roles;

    /// IVRFStorage
    mapping(uint => VRFRequest) private requestMap;

    /// IJackpotStorage
    mapping(address => uint) private jackpots;

    /// IConfigStorage
    Config public config;

    Counters private counters;

    Scope private scope;

    /// ISignedNftStorage
    mapping(uint64 => uint) private usedExternalIds;

    constructor() {
        _disableInitializers();
    }

    function init(string memory name_, string memory symbol_, string memory baseUri_, uint64 maxSupply, uint32 begin, uint32 end, address signer) initializer public virtual {
        counters.nextBoxId = FIRST_ID; // starts from 1
        name = name_;
        symbol = symbol_;
        baseUri = baseUri_;
        scope.maxSupply = maxSupply;
        scope.begin = begin;
        scope.end = end;
        scope.alwaysBurn = 1;
        config.signer = signer;
    }

    function _name() internal view override returns (string storage) {
        return name;
    }

    function _symbol() internal view override returns (string storage) {
        return symbol;
    }

    function _baseURI() internal view override returns (string storage) {
        return baseUri;
    }

    function _baseURI(string memory baseUri_) internal override {
        baseUri = baseUri_;
    }

    function _balances(address user) internal view override returns (NFTCounter storage) {
        return userToRaritiesCounters[user];
    }

    function _nft(IdType tokenId, NFTDef memory definition) internal override {
        nfts[tokenId] = definition;
    }

    function _nft(IdType key) internal view override returns (NFTDef storage) {
        return nfts[key];
    }

    function _deleteNft(IdType key) internal override {
        delete nfts[key];
    }

    function _operatorApprovals(address owner, address operator) internal view override returns (bool) {
        return operatorApprovals[owner][operator];
    }

    function _operatorApprovals(address owner, address operator, bool value) internal override {
        if (!value) {
            delete operatorApprovals[owner][operator];
            return;
        }
        operatorApprovals[owner][operator] = true;
    }

    /// IPrizeStorage
    function _rarity(uint level) internal view override returns (RarityDef storage) {
        return rarities[level];
    }

    function _rarity(uint level, Probability probability) internal override {
        rarities[level].probability = probability;
    }

    function _prizes(uint32 id) internal view override returns (PrizeDef storage) {
        return prizes[id];
    }

    function _delPrize(uint32 id) internal override {
        delete prizes[id];
    }

    function _getPrizeIdByNft(address collection, uint tokenId) internal view override returns (uint32) {
        return uniquePrize[keccak256(abi.encodePacked(collection, tokenId))];
    }

    function _addPrizeIdByNft(address collection, uint tokenId, uint32 id) internal override {
        uniquePrize[keccak256(abi.encodePacked(collection, tokenId))] = id;
    }

    function _removePrizeIdByNft(address collection, uint tokenId) internal override {
        delete uniquePrize[keccak256(abi.encodePacked(collection, tokenId))];
    }

    /// IPriceStorage
    function _price(address token) internal override view returns (uint) {
        return prices[token];
    }

    function _price(address token, uint price) internal override {
        prices[token] = price;
    }

    function _delPrice(address token) internal override {
        delete prices[token];
    }

    function _addTokenToPrice(address token) internal override {
        priceTokens.push(token);
    }

    /// IAccessControlStorage
    function _roles(bytes32 role) internal view override returns (RoleData storage) {
        return roles[role];
    }

    /// IConfigStorage
    function _config() internal override view returns (Config storage) {
        return config;
    }

    /// IVRFStorage
    function _vrfCoordinator() internal override view returns (address) {
        return config.vrfCoordinator;
    }

    function _keyHash() internal override view returns (bytes32) {
        return config.keyHash;
    }

    function _subscriptionId() internal override view returns (uint64) {
        return config.subscriptionId;
    }

    function _requestConfirmations() internal override view returns (uint16) {
        return config.requestConfirmations;
    }

    function _callbackGasLimit() internal override view returns (uint32) {
        return config.callbackGasLimit;
    }

    function _requestMap(uint requestId) internal override view returns (VRFRequest storage) {
        return requestMap[requestId];
    }

    function _delRequest(uint requestId) internal override {
        delete requestMap[requestId];
    }

    function _requestMap(uint requestId, uint8 requestType, IdType id, uint16 count) internal override {
        VRFRequest storage request = requestMap[requestId];
        request.firstTokenId = id;
        request.count = count;
        request.requestType = requestType;
    }

    /// ILootBoxStorage
    function _nextTokenId(uint count) internal override returns (IdType) {
        if (count == 0) {
            return counters.nextBoxId;
        }
        IdType result = counters.nextBoxId;
        counters.nextBoxId = counters.nextBoxId.next(count);
        return result;
    }

    function _totalSupplyWithBoost() internal override view returns (uint64) {
        return counters.nextBoxId.unwrap() - 1 + counters.boostAdding;
    }

    function _scope() internal view override returns (Scope storage) {
        return scope;
    }

    function _scope(Scope memory scope_) internal override {
        scope = scope_;
    }

    function _counters() internal view override returns (Counters memory) {
        return counters;
    }

    function _increaseClaimRequestCounter(uint16 amount) internal override {
        counters.claimRequestCounter += amount;
    }

    function _decreaseClaimRequestCounter(uint16 amount) internal override {
        counters.claimRequestCounter -= amount;
    }

    function _addBoostAdding(uint32 amount) internal override {
        counters.boostAdding += amount;
    }

    /// IJackpotStorage
    function _jackpot(address token) internal override view returns (uint) {
        return jackpots[token];
    }

    function _addJackpot(address token, int amount) internal override {
        if (amount < 0) {
            jackpots[token] -= uint(-amount);
        }
        else {
            jackpots[token] += uint(amount);
        }
    }

    function _listJackpots() internal override view returns (address[] storage) {
        return priceTokens;
    }

    function _jackpotShare() internal override view returns (Probability) {
        return config.jackpotShare;
    }

    function _addEmptyCounter(int32 amount) internal override {
        if (amount > 0) {
            counters.emptyCounter += uint32(amount);
        }
        else {
            counters.emptyCounter -= uint32(-amount);
        }
    }

    /// ISignedNftStorage
    function _signer() internal override view returns (address) {
        return config.signer;
    }

    function _signer(address newSigner) internal override {
        config.signer = newSigner;
    }

    function _getUsedAndSet(uint64 externalId) internal override returns (bool result) {
        result = usedExternalIds[externalId] != 0;
        usedExternalIds[externalId] = 1;
    }

    function _getUsed(uint64 externalId) internal view override returns (bool) {
        return usedExternalIds[externalId] != 0;
    }

}

