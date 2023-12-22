// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./IERC721.sol";
import "./IERC721Enumerable.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./ERC721Burnable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./ERC721Holder.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";

contract Tournament is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum TicketCollectionStatus {
        PENDING,
        OPEN,
        CLOSE
    }

    enum TournamentStatus {
        PENDING,
        OPEN,
        CLOSE
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "It is Not an operator role"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "It is Not an admin role"
        );
        _;
    }

    struct TicketCollection {
        uint256 ticketCollectionId;
        uint256 price;
        address tokenBuy;
        uint256 totalNumberOfTickets;
        mapping(address => uint256) numberOfTickets;
        address[] listOwnerTicket;
        TicketCollectionStatus status;
    }

    struct TournamentDetail {
        uint256 tournamentId;
        uint256 ticketCollectionId;
        string gameId;
        uint256 totalTickets;
        address revenueAddress;
        TournamentStatus status;
    }

    mapping(uint256 => TicketCollection) public listTicketCollection;
    mapping(address => bool) public whiteListPaymentToken;
    mapping(uint256 => TournamentDetail) public tournamentDetails;
    mapping(address => mapping(address => uint256)) public ticketRevenue;
    uint256[] listCollection;

    event CreateTicketCollectionEvent(
        uint256 ticketCollectionId,
        uint256 price,
        address tokenBuy
    );

    event BuyTicketEvent(
        uint256 ticketCollectionId,
        uint256 numberOfTickets,
        address buyer
    );

    event UseTicketEvent(uint256 ticketCollectionid, uint256 tournamentId);

    event TournamentEvent(TournamentDetail tournamentDetail);

    event ClaimRevenueTicketEvent(
        address revenueAddress,
        address token,
        uint256 value
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    function setWhiteListPaymentToken(
        address token,
        bool status
    ) public onlyAdmin {
        whiteListPaymentToken[token] = status;
    }

    function createTicketCollection(
        uint256 ticketCollectionId,
        uint256 price,
        address tokenBuy
    ) public onlyOperator {
        require(price > 0, "The value of priceTicket must be greater than 0");
        require(
            whiteListPaymentToken[tokenBuy],
            "The token buy is not whitelisted"
        );
        TicketCollection storage ticketCollection = listTicketCollection[
            ticketCollectionId
        ];
        require(
            ticketCollection.status == TicketCollectionStatus.PENDING,
            "The ticket collection status is invalid"
        );
        ticketCollection.ticketCollectionId = ticketCollectionId;
        ticketCollection.price = price;
        ticketCollection.tokenBuy = tokenBuy;
        ticketCollection.status = TicketCollectionStatus.OPEN;

        listCollection.push(ticketCollectionId);
        emit CreateTicketCollectionEvent(ticketCollectionId, price, tokenBuy);
    }

    function createTournament(
        uint256 tournamentId,
        uint256 ticketCollectionId,
        string memory gameId,
        address revenueAddress
    ) public onlyOperator {
        require(
            revenueAddress != address(0),
            "The revenue address is not address(0)"
        );
        TicketCollection storage ticketCollection = listTicketCollection[
            ticketCollectionId
        ];
        require(
            ticketCollection.status == TicketCollectionStatus.OPEN,
            "The ticket collection status is invalid"
        );
        TournamentDetail storage tournament = tournamentDetails[tournamentId];
        require(
            tournament.status == TournamentStatus.PENDING,
            "The tournament status is invalid"
        );
        tournament.tournamentId = tournamentId;
        tournament.ticketCollectionId = ticketCollectionId;
        tournament.gameId = gameId;
        tournament.revenueAddress = revenueAddress;
        tournament.status = TournamentStatus.OPEN;

        emit TournamentEvent(tournament);
    }

    function closeTournament(uint256 tournamentId) public onlyOperator {
        TournamentDetail storage tournament = tournamentDetails[tournamentId];
        require(
            tournament.status == TournamentStatus.OPEN,
            "The tournament is closed"
        );
        tournament.status = TournamentStatus.CLOSE;

        emit TournamentEvent(tournament);
    }

    function buyTicket(
        uint256 ticketCollectionId,
        uint256 price,
        address tokenBuy,
        uint256 quantity
    ) public {
        TicketCollection storage ticketCollection = listTicketCollection[
            ticketCollectionId
        ];
        require(
            ticketCollection.status == TicketCollectionStatus.OPEN,
            "The ticket collection is closed"
        );
        require(ticketCollection.price == price, "It is invalid fare");
        require(
            ticketCollection.tokenBuy == tokenBuy,
            "It is an invalid token buy"
        );
        require(
            quantity > 0,
            "The number of buying tickets must be greater than 0"
        );

        ticketCollection.numberOfTickets[msg.sender] = ticketCollection
            .numberOfTickets[msg.sender]
            .add(quantity);
        ticketCollection.totalNumberOfTickets = ticketCollection
            .totalNumberOfTickets
            .add(quantity);

        SafeERC20.safeTransferFrom(
            IERC20(tokenBuy),
            msg.sender,
            address(this),
            quantity.mul(ticketCollection.price)
        );

        ticketCollection.listOwnerTicket.push(msg.sender);

        emit BuyTicketEvent(ticketCollectionId, quantity, msg.sender);
    }

    function useTicket(
        uint256 ticketCollectionId,
        uint256 tournamentId
    ) public {
        TicketCollection storage ticketCollection = listTicketCollection[
            ticketCollectionId
        ];
        TournamentDetail storage tournament = tournamentDetails[tournamentId];
        require(
            tournament.status == TournamentStatus.OPEN,
            "The tournament is closed"
        );
        require(
            tournament.ticketCollectionId == ticketCollectionId,
            "It is an invalid ticket collection"
        );
        require(
            ticketCollection.numberOfTickets[msg.sender] > 0,
            "The number of tickets is not enough"
        );
        ticketCollection.numberOfTickets[msg.sender] = ticketCollection
            .numberOfTickets[msg.sender]
            .sub(1);
        tournament.totalTickets += 1;
        ticketRevenue[tournament.revenueAddress][
            ticketCollection.tokenBuy
        ] += ticketCollection.price;

        emit UseTicketEvent(ticketCollectionId, tournamentId);
    }

    function getValueRevenue(
        address revenueAddress,
        address tokenBuy
    ) public view returns (uint256) {
        uint256 value = ticketRevenue[revenueAddress][tokenBuy];
        return value;
    }

    function claimRevenueTicket(address token) public {
        uint256 value = getValueRevenue(msg.sender, token);
        require(value > 0, "It is not enough revenue");

        SafeERC20.safeTransfer(IERC20(token), msg.sender, value);

        ticketRevenue[msg.sender][token] = 0;

        emit ClaimRevenueTicketEvent(msg.sender, token, value);
    }

    function getTotalTicket(
        uint256 collectionId
    ) public view returns (uint256) {
        TicketCollection storage ticketCollection = listTicketCollection[
            collectionId
        ];
        return ticketCollection.totalNumberOfTickets;
    }

    function getNumberOfTicket(
        uint256 collectionId,
        address owner
    ) public view returns (uint256) {
        TicketCollection storage ticketCollection = listTicketCollection[
            collectionId
        ];
        return ticketCollection.numberOfTickets[owner];
    }

    function getListTicketOfUser(
        address user
    ) public view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory ids = new uint256[](listCollection.length);
        uint256[] memory numbers = new uint256[](listCollection.length);

        for (uint256 i = 0; i < listCollection.length; i++) {
            uint256 collectionId = listCollection[i];
            uint256 numberOfTicketOfUserOfCollection = listTicketCollection[
                collectionId
            ].numberOfTickets[user];
            if (numberOfTicketOfUserOfCollection > 0) {
                ids[i] = collectionId;
                numbers[i] = numberOfTicketOfUserOfCollection;
            }
        }

        return (ids, numbers);
    }

    function getListAddressOfCollection(
        uint256 collectionId
    ) public view returns (address[] memory, uint256[] memory) {
        TicketCollection storage ticketCollection = listTicketCollection[
            collectionId
        ];
        address[] memory addr = new address[](
            ticketCollection.listOwnerTicket.length
        );
        uint256[] memory numberOfTickets = new uint256[](
            ticketCollection.listOwnerTicket.length
        );

        for (uint256 i = 0; i < ticketCollection.listOwnerTicket.length; i++) {
            address owner = ticketCollection.listOwnerTicket[i];
            uint256 number = ticketCollection.numberOfTickets[owner];
            if (number > 0) {
                addr[i] = owner;
                numberOfTickets[i] = number;
            }
        }

        return (addr, numberOfTickets);
    }
}

