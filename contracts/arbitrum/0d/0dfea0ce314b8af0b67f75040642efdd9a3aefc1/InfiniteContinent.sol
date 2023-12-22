// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./Pricing.sol";

contract InfiniteContinent is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, ERC721EnumerableUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using ECDSAUpgradeable for bytes32;
    using AddressUpgradeable for address payable;
    using Pricing for uint;

    enum Community{
        None,
        A,
        B
    }

    CountersUpgradeable.Counter internal _idCounterPurchase;
    uint _idCounterPresent;
    address _cashier;
    address _giftTokenAddress;
    // gift NFT official holder
    address _officialAddress;
    address _verifierAddress;

    string _baseUri;
    string public contractURI;

    mapping(address => bool) _managers;
    mapping(Community => uint) _records;

    event CashierChanged(address cashier, address preCashier);
    event ManagerChanged(address manager, bool status);
    event Present(address purchaser, Community community);

    modifier onlyManager(){
        require(_managers[msg.sender], "unauthorized");
        _;
    }

    function __InfiniteContinent_init(
        string memory name,
        string memory symbol,
        address cashier,
        address giftTokenAddress,
        address officialAddress,
        address verifierAddress,
        uint idCounterPresent
    ) public initializer() {
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ReentrancyGuard_init();
        __ERC721_init(name, symbol);

        _pause();
        _cashier = cashier;
        _giftTokenAddress = giftTokenAddress;
        _officialAddress = officialAddress;
        _verifierAddress = verifierAddress;
        _idCounterPurchase._value = 201;
        _idCounterPresent = idCounterPresent;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function setBaseURI(string memory newBaseURI) external onlyManager {
        _baseUri = newBaseURI;
    }

    function setContractURI(string memory newContractURI) external onlyManager {
        contractURI = newContractURI;
    }

    function purchase(Community community, bytes calldata signature) external payable nonReentrant whenNotPaused {
        uint currentId = _idCounterPurchase.current();
        require(currentId <= 10000, "exceed max supply");
        uint price = currentId.tokenPricing();
        _idCounterPurchase.increment();

        uint value = msg.value;
        require(value >= price, "insufficient eth");
        uint refund;
    unchecked{
        refund = value - price;
    }
        // present gift NFT
        address purchaser = msg.sender;
        if (community == Community.A || community == Community.B) {
            require(
                _verifierAddress == keccak256(
                abi.encodePacked(
                    community,
                    purchaser
                )
            ).toEthSignedMessageHash().recover(signature),
                "invalid sig"
            );

            address officialAddress = _officialAddress;
            IERC721Upgradeable giftToken = IERC721Upgradeable(_giftTokenAddress);
            uint idPresentStart = _idCounterPresent;
            uint idPresentEnd = idPresentStart + 5;
            _idCounterPresent = idPresentEnd;
            for (; idPresentStart < idPresentEnd; ++idPresentStart) {
                giftToken.transferFrom(officialAddress, purchaser, idPresentStart);
            }

            _records[community] += 1;
            emit Present(purchaser, community);
        }

        _safeMint(purchaser, currentId);
        if (refund != 0) {
            payable(purchaser).sendValue(refund);
        }
    }

    function setCashier(address newCashier) external onlyOwner {
        address preCashier = _cashier;
        _cashier = newCashier;
        emit CashierChanged(newCashier, preCashier);
    }

    function getCashier() external view returns (address){
        return _cashier;
    }

    function setManagerStatus(address manager, bool status) external onlyOwner {
        _managers[manager] = status;
        emit ManagerChanged(manager, status);
    }

    function getManagerStatus(address manager) external view returns (bool){
        return _managers[manager];
    }

    function setVerifierAddress(address newVerifierAddress) external onlyManager {
        _verifierAddress = newVerifierAddress;
    }

    function getVerifierAddress() external view returns (address){
        return _verifierAddress;
    }

    function setGiftTokenAddress(address newGiftTokenAddress) external onlyManager {
        _giftTokenAddress = newGiftTokenAddress;
    }

    function getGiftTokenAddress() external view returns (address){
        return _giftTokenAddress;
    }

    function setOfficialAddress(address newOfficialAddress) external onlyManager {
        _officialAddress = newOfficialAddress;
    }

    function getOfficialAddress() external view returns (address){
        return _officialAddress;
    }

    function getCommunityRecord(Community community) external view returns (uint){
        return _records[community];
    }

    function getNextTokenPrice() external view returns (uint){
        return _idCounterPurchase.current().tokenPricing();
    }

    function mintReservedTokens(uint[] calldata tokenIds, address[] calldata recipients) external onlyManager {
        uint len = tokenIds.length;
        require(len == recipients.length, "length mismatched");
        for (uint i = 0; i < len; ++i) {
            uint tokenId = tokenIds[i];
            require(tokenId <= 200 && tokenId != 0, "invalid token id");
            _safeMint(recipients[i], tokenIds[i]);
        }
    }

    function flipPause() external onlyManager {
        paused() ? _unpause() : _pause();
    }

    function withdrawPayment(uint amount) external {
        address cashier = msg.sender;
        require(cashier == _cashier, "unauthorized");
        payable(cashier).sendValue(amount);
    }

    uint[40] private __gap;
}

