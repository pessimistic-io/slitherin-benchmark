// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Upgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./NonblockingLzAppUpgradeable.sol";
import "./ERC721AUpgradeable.sol";
import "./IRandomizerAdapter.sol";
import "./ITickets.sol";
import "./IWETHWithdrawAdapter.sol";
import "./IWETH.sol";
import "./IACLManager.sol";

contract Bids is
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC721AUpgradeable,
    ERC721HolderUpgradeable,
    ERC1155HolderUpgradeable,
    NonblockingLzAppUpgradeable
{
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    IWETH public WETH;
    ITickets public tickets;
    uint256 public ticketId;
    IACLManager public aclManager;
    address public layer1Raffles;
    address public rewardsCollection;
    IRandomizerAdapter public randomizerAdapter;
    IWETHWithdrawAdapter public wethWithdrawAdapter;
    string public baseUri;
    uint256 public fee;

    CountersUpgradeable.Counter private _raffleIdTracker;

    enum Status {
        Unpurchased,
        Purchased,
        Drawing,
        Drawn
    }

    struct RaffleInfo {
        uint256 start;
        uint256 end;
        uint256 winnerNumber;
        uint256 tokenId;
        uint256 price;
        address winner;
        Status status;
    }

    mapping(uint256 => RaffleInfo) public raffles;

    event SetLayer2Endpoint(address indexed _layer2Endpoint);
    event SetRandomizerAdapter(address indexed adapter);
    event SetRewardsCollection(address indexed collection);
    event SetWETHWithdrawAdapter(address indexed adapter);
    event SetFee(uint256 fee);
    event SetBaseUri(string baseUri);
    event SetLayer1Raffles(address indexed layer1Raffles);
    event Bid(address indexed bidder, uint256 amount);
    event WithdrawWETHToLayer1(uint256 amount, bytes data);
    event CreateRaffle(
        uint256 indexed raffleId,
        uint256 start,
        uint256 end,
        address indexed rewardsCollection,
        uint256 tokenId,
        uint256 listPrice
    );
    event Draw(uint256 indexed raffleId);
    event DrawCallback(
        uint256 indexed raffleId,
        uint256 randomNumber,
        uint256 winnerNumber,
        address indexed winner
    );

    modifier onlyRandomizerAdapter() virtual {
        require(
            address(randomizerAdapter) == msg.sender,
            "ONLY_RANDOMIZER_ADAPTER"
        );
        _;
    }

    modifier onlyGovernance() {
        require(aclManager.isGovernance(msg.sender), "ONLY_GOVERNANCE");
        _;
    }

    modifier onlyOperator() {
        require(aclManager.isOperator(msg.sender), "ONLY_OPERATOR");
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(
            aclManager.isEmergencyAdmin(msg.sender),
            "ONLY_EMERGENCY_ADMIN"
        );
        _;
    }

    // constructor(
    //     address _weth,
    //     address _tickets,
    //     address _layer1Raffles,
    //     address _rewardsCollection,
    //     address _randomizerAdapter,
    //     address _wethWithdrawAdapter,
    //     address _endpoint,
    //     address _aclManager
    // ) ERC721A("Bids", "BIDS") Ownable() Pausable() NonblockingLzApp(_endpoint) {
    //     WETH = IWETH(_weth);
    //     tickets = ITickets(_tickets);
    //     _setLayer1Raffles(_layer1Raffles);
    //     _setRewardsCollection(_rewardsCollection);
    //     _setRandomizerAdapter(_randomizerAdapter);
    //     _setWETHWithdrawAdapter(_wethWithdrawAdapter);
    //     aclManager = IACLManager(_aclManager);
    // }

    function initialize(
        address _weth,
        address _tickets,
        address _layer1Raffles,
        address _rewardsCollection,
        address _randomizerAdapter,
        address _wethWithdrawAdapter,
        address _endpoint,
        address _aclManager
    ) public initializer initializerERC721A {
        __ERC721A_init("Bids", "BIDS");
        __Ownable_init();
        __Pausable_init();
        __NonblockingLzAppUpgradeable_init(_endpoint);

        WETH = IWETH(_weth);
        tickets = ITickets(_tickets);
        _setLayer1Raffles(_layer1Raffles);
        _setRewardsCollection(_rewardsCollection);
        _setRandomizerAdapter(_randomizerAdapter);
        _setWETHWithdrawAdapter(_wethWithdrawAdapter);
        aclManager = IACLManager(_aclManager);

        ticketId = 1;
        fee = 20;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function pause() external onlyEmergencyAdmin {
        _pause();
    }

    function unpause() external onlyEmergencyAdmin {
        _unpause();
    }

    function setRandomizerAdapter(
        address _randomizerAdapter
    ) external onlyGovernance {
        _setRandomizerAdapter(_randomizerAdapter);
    }

    function _setRandomizerAdapter(address _randomizerAdapter) internal {
        randomizerAdapter = IRandomizerAdapter(_randomizerAdapter);

        emit SetRandomizerAdapter(_randomizerAdapter);
    }

    function setRewardsCollection(
        address _rewardsCollection
    ) external onlyGovernance {
        _setRewardsCollection(_rewardsCollection);
    }

    function _setRewardsCollection(address _rewardsCollection) internal {
        rewardsCollection = _rewardsCollection;

        emit SetRewardsCollection(_rewardsCollection);
    }

    function setWETHWithdrawAdapter(
        address _wethWithdrawAdapter
    ) external onlyGovernance {
        _setWETHWithdrawAdapter(_wethWithdrawAdapter);
    }

    function _setWETHWithdrawAdapter(address _wethWithdrawAdapter) internal {
        wethWithdrawAdapter = IWETHWithdrawAdapter(_wethWithdrawAdapter);

        emit SetWETHWithdrawAdapter(_wethWithdrawAdapter);
    }

    function setFee(uint256 _fee) external onlyGovernance {
        uint256 minPrice = tickets.getMinPrice(ticketId);
        uint256 fullPrice = tickets.getFullPrice(ticketId);
        require(fullPrice < (100 + _fee) * minPrice / 100, "FEE_ERROR");

        fee = _fee;

        emit SetFee(_fee);
    }

    function setLayer1Raffles(address _layer1Raffles) external onlyGovernance {
        _setLayer1Raffles(_layer1Raffles);
    }

    function _setLayer1Raffles(address _layer1Raffles) internal {
        layer1Raffles = _layer1Raffles;

        emit SetLayer1Raffles(_layer1Raffles);
    }

    function setBaseUri(string memory _baseUri) external onlyOwner {
        baseUri = _baseUri;

        emit SetBaseUri(_baseUri);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155ReceiverUpgradeable, ERC721AUpgradeable) returns (bool) {
        return
            interfaceId == type(IERC1155ReceiverUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function bidWithETH(
        uint256 amount,
        bytes memory data
    ) external payable whenNotPaused {
        uint256 paymentAmount = tickets.getFullPrice(ticketId) * amount;
        tickets.mintWhenBidding{value: paymentAmount}(ticketId, amount, data);

        tickets.burn(address(this), ticketId, amount);
        _bid(msg.sender, amount);

        uint256 refund = msg.value - paymentAmount;
        if (refund > 0) {
            AddressUpgradeable.sendValue(payable(msg.sender), refund);
        }
    }

    function bid(uint256 amount) public whenNotPaused {
        tickets.burn(msg.sender, ticketId, amount);
        _bid(msg.sender, amount);
    }

    function _bid(address recipient, uint256 amount) internal {
        _mint(recipient, amount);

        emit Bid(recipient, amount);
    }

    function withdrawWETHToLayer1(
        uint256 amount,
        bytes memory data
    ) external onlyOperator {
        _withdrawWETHToLayer1(amount, data);
    }

    function _withdrawWETHToLayer1(uint256 amount, bytes memory data) internal {
        require(
            address(wethWithdrawAdapter) != address(0),
            "WETH_WITHDRAW_ADAPTER_NOT_SET"
        );
        require(layer1Raffles != address(0), "LAYER1_RAFFLES_NOT_SET");

        tickets.withdrawWETH(ticketId, amount);

        WETH.approve(address(wethWithdrawAdapter), amount);
        wethWithdrawAdapter.withdraw(layer1Raffles, amount, data);

        emit WithdrawWETHToLayer1(amount, data);
    }

    function _createRaffle(uint256 price, uint256 tokenId) internal {
        require(price > 0, "PRICE_ERROR");
        _raffleIdTracker.increment();

        uint256 raffleId = _raffleIdTracker.current();

        RaffleInfo storage raffleInfo = raffles[raffleId];

        uint256 start = raffles[raffleId - 1].end + 1;
        uint256 length = _ceilDiv(
            price * (100 + fee),
            tickets.getFullPrice(ticketId) * 100
        );
        uint256 end = raffles[raffleId - 1].end + length;
        raffleInfo.start = start;
        raffleInfo.end = end;
        raffleInfo.price = price;
        raffleInfo.tokenId = tokenId;
        raffleInfo.status = Status.Purchased;

        emit CreateRaffle(
            raffleId,
            start,
            end,
            rewardsCollection,
            tokenId,
            price
        );
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function draw(uint256 raffleId) external onlyOperator {
        RaffleInfo storage raffleInfo = raffles[raffleId];
        uint256 tokenId = _nextTokenId() - 1;
        require(raffleInfo.status == Status.Purchased, "UNPURCHASED");
        require(raffleInfo.end <= tokenId, "BID_NOT_END");

        raffleInfo.status = Status.Drawing;

        randomizerAdapter.requestRandomNumber(raffleId);

        emit Draw(raffleId);
    }

    function drawCallback(
        uint256 raffleId,
        uint256 randomNumber
    ) external onlyRandomizerAdapter {
        RaffleInfo storage raffleInfo = raffles[raffleId];
        require(raffleInfo.status == Status.Drawing, "NOT_RAFFLING");
        raffleInfo.winnerNumber =
            raffleInfo.start +
            (randomNumber % (raffleInfo.end - raffleInfo.start + 1));

        address to = ownerOf(raffleInfo.winnerNumber);
        IERC721Upgradeable(rewardsCollection).safeTransferFrom(
            address(this),
            to,
            raffleInfo.tokenId
        );
        raffleInfo.winner = to;

        raffleInfo.status = Status.Drawn;

        tickets.addProfit(
            ticketId,
            tickets.getMinPrice(ticketId) * (raffleInfo.end - raffleInfo.start + 1) - raffleInfo.price
        );

        emit DrawCallback(raffleId, randomNumber, raffleInfo.winnerNumber, to);
    }

    function isAvailableToDraw(uint256 raffleId) external view returns (bool) {
        RaffleInfo memory raffleInfo = raffles[raffleId];
        uint256 tokenId = _nextTokenId() - 1;
        return raffleInfo.status == Status.Purchased && raffleInfo.end <= tokenId;
    }

    function getCurrentRaffleId() external view returns (uint256) {
        return _raffleIdTracker.current();
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal virtual override {
        (uint256 tokenId, uint256 price) = abi.decode(
            _payload,
            (uint256, uint256)
        );

        _createRaffle(price, tokenId);
    }
}

