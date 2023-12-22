// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
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
import "./NFT721Ticket.sol";
import "./TicketFactory.sol";
import "./ITicketCollectionFactory.sol";

contract Tournament is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address public ticketCollectionFactory;

    enum TicketCollectionStatus {
        INACTIVE,
        ACTIVE
    }

    enum TournamentStatus {
        PENDING,
        OPEN,
        CLOSE
    }

    enum RedeemRequestStatus {
        UNPROCESSED,
        PROCESSING,
        COMPLETED
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
        address ticketCollectionAddress;
        uint256 price;
        address tokenBuy;
        uint256 totalNumberOfTickets;
        mapping(address => uint256) numberOfTickets;
        address[] listTicketOwners;
        TicketCollectionStatus status;
    }

    struct TournamentDetail {
        uint256 tournamentId;
        address ticketCollectionAddress; 
        string gameId;
        uint256 totalTickets;
        address revenueAddress;
        TournamentStatus status;
    }

    struct DepositTicketDetail {
        address ticketCollectionAddress;
        uint256[] tokenIds;
    }

    mapping(address => TicketCollection) public listTicketCollection;
    mapping(address => bool) public whiteListPaymentToken;
    mapping(uint256 => TournamentDetail) public tournamentDetails;
    mapping(address => mapping(address => uint256)) public ticketRevenue;
    mapping(address => mapping(address => uint256[])) public depositTicketOfUser;
    mapping(uint256 => RedeemRequest) public listRedeemRequests;
    mapping(address => bool) public whiteListSigner;
    address[] public listTicketCollectionAddress;

    event CreateTicketCollectionEvent(
        address ticketCollectionAddress,
        uint256 price,
        address tokenBuy
    );

    event CreateRedeemRequestEvent(uint256 requestId, TicketQuantity[] ticketCollectionAddress, address revenueAddress, address tokenAddress);
    event ClaimTicketEvent(uint256 requestId);

    event UseTicketEvent(address ticketCollectionAddress, uint256 tournamentId);

    event TournamentEvent(TournamentDetail tournamentDetail);
    event BuyNFTEvent(address ticketCollectionAddress,uint256 quantity, uint256 price);
    event DepositTicketEvent(DepositTicketDetail[] depositTicket);

    event WithdrawTicketEvent(TicketQuantity[] ticketQuantity);
    

    event ClaimRevenueTicketEvent(
        address revenueAddress,
        address token,
        uint256 value
    );

    struct RedeemRequest {
        uint256 requestId;
        address creator;
        address[] ticketCollectionAddresses; // a list of ticket type collections (bronze, silver, ...)
        mapping(address => uint256) numberOfTickets; // mapping: ticketTypeCollectionId -> number of tickets
        address revenueAddress;
        address tokenAddress;
        RedeemRequestStatus status; // request status
    }

    struct TicketQuantity {
        address ticketCollectionAddress; // ticketTypeCollectionId
        uint256 quantity; // number of tickets
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    function setTicketCollectionFactory(address ticketCollectionFactoryAddress) public onlyAdmin {
        require(ticketCollectionFactoryAddress != address(0), "Operations: Ticket collection address cannot be zero");
        ticketCollectionFactory = ticketCollectionFactoryAddress;
    } 

     function setWhiteListSigner(address signer, bool status) public  onlyAdmin(){
        require(signer != address(0), "Operations: Signer address cannot be zero");
        whiteListSigner[signer] = status;
    }

    function checkWhiteListSigner(address signer) public view returns(bool) {
        return whiteListSigner[signer];
    }

    function setWhiteListPaymentToken(
        address token,
        bool status
    ) public onlyAdmin {
        whiteListPaymentToken[token] = status;
    }

    /// claim Game points to a list of tickets with diff/same ticket types
    function createRedeemRequest(
        uint256 requestId,
        address revenueAddress,
        address tokenAddress,
        TicketQuantity[] memory rewardClaimTickets
    ) public {
        RedeemRequest storage redeemRequest = listRedeemRequests[requestId];
        
        require(redeemRequest.status == RedeemRequestStatus.UNPROCESSED, "Redeem request already exists");
        require(whiteListPaymentToken[tokenAddress] , "Token address is not a whitelisted payment token");

        for(uint256 i = 0 ; i < rewardClaimTickets.length; i++) {
            TicketCollection storage ticketCollection = listTicketCollection[rewardClaimTickets[i].ticketCollectionAddress];
            require(
                ticketCollection.status == TicketCollectionStatus.ACTIVE,
                "The ticket collection status is invalid"
            );
            redeemRequest.requestId = requestId;
            redeemRequest.creator = msg.sender;
            redeemRequest.ticketCollectionAddresses.push(rewardClaimTickets[i].ticketCollectionAddress);
            redeemRequest.numberOfTickets[rewardClaimTickets[i].ticketCollectionAddress] = rewardClaimTickets[i].quantity;
            redeemRequest.revenueAddress = revenueAddress;
            redeemRequest.tokenAddress = tokenAddress;
            redeemRequest.status = RedeemRequestStatus.PROCESSING;
        } 

        emit CreateRedeemRequestEvent(requestId, rewardClaimTickets, revenueAddress, tokenAddress);
    }

    /// After the request has been approved, the tickets will be minted to the sender addr
    function claimTicket(uint256 requestId, bytes memory signature) external {

        address signer = verify(requestId, signature);

        RedeemRequest storage redeemRequest = listRedeemRequests[requestId];
        require(redeemRequest.status == RedeemRequestStatus.PROCESSING, "Request does not exist");
        require(redeemRequest.creator == msg.sender, "You are not the owner of the request");

        require(whiteListSigner[signer], "Invalid signer");
       

        for(uint256 i = 0 ; i < redeemRequest.ticketCollectionAddresses.length; i ++) {
            for(uint256 j = 0 ; j < redeemRequest.numberOfTickets[redeemRequest.ticketCollectionAddresses[i]] ; j ++) {
                NFT721Ticket(redeemRequest.ticketCollectionAddresses[i]).safeMint(msg.sender);
                TicketCollection storage ticketCollection = listTicketCollection[redeemRequest.ticketCollectionAddresses[i]];
                ticketRevenue[redeemRequest.revenueAddress][redeemRequest.tokenAddress] -= ticketCollection.price;
            }
        }
        redeemRequest.status = RedeemRequestStatus.COMPLETED;

        emit ClaimTicketEvent(requestId);

    }

    /// Withdraw tickets from the deposit SC
    function withdrawTicket(TicketQuantity[] memory withdrawTickets) public {

        for(uint256 i=0 ; i< withdrawTickets.length; i++) {
            for(uint256 j = withdrawTickets[i].quantity ; j > 0 ; j--) {
                address ticketCollectionAddress = withdrawTickets[i].ticketCollectionAddress;
                uint256 length = depositTicketOfUser[msg.sender][ticketCollectionAddress].length;
                uint256 tokenId = depositTicketOfUser[msg.sender][ticketCollectionAddress][length -1];
                IERC721(withdrawTickets[i].ticketCollectionAddress).safeTransferFrom(address(this), msg.sender, tokenId);
                depositTicketOfUser[msg.sender][ticketCollectionAddress].pop();
            }

        }

        emit WithdrawTicketEvent(withdrawTickets);
       
    }

    function createTicketCollection(
        uint256 price,
        address tokenBuy,
        string memory _name,
        string memory _symbol,
        string memory _baseURI
    ) public onlyOperator returns(address) {

        require(whiteListPaymentToken[tokenBuy] , "Token buy is not a whitelisted payment token");
        require(price > 0, "Price must be greater than zero");

        address nft721Ticket = ITicketCollectionFactory(ticketCollectionFactory).createTicketCollection(_name, _symbol, _baseURI);

        TicketCollection storage ticketCollection = listTicketCollection[nft721Ticket];
        ticketCollection.ticketCollectionAddress = nft721Ticket;
        ticketCollection.price = price;
        ticketCollection.tokenBuy = tokenBuy;
        ticketCollection.status = TicketCollectionStatus.ACTIVE;

        listTicketCollectionAddress.push(nft721Ticket);

        emit CreateTicketCollectionEvent(nft721Ticket, price, tokenBuy);
        return address(nft721Ticket);
    }

    function setBaseURI(address ticketCollectionAddress,string memory baseURI) public onlyAdmin{
        NFT721Ticket(ticketCollectionAddress).setBaseURI(baseURI);
    }


    function buyNFT(address ticketCollectionAddress, uint256 quantity) public {
        require(quantity > 0, "Quantity must be greater than zero");
        TicketCollection storage ticketCollection = listTicketCollection[ticketCollectionAddress];

        IERC20(ticketCollection.tokenBuy).safeTransferFrom(
            address(msg.sender),
            address(this),
            ticketCollection.price * quantity
        );
        for(uint256 i = 0 ; i < quantity ; i ++) {
            NFT721Ticket(ticketCollection.ticketCollectionAddress).safeMint(msg.sender);
        }

        emit BuyNFTEvent(ticketCollectionAddress,quantity, ticketCollection.price);
    }

    function createTournament(
        uint256 tournamentId,
        address ticketCollectionAddress,
        string memory gameId,
        address revenueAddress
    ) public onlyOperator {
        require(
            revenueAddress != address(0),
            "The revenue address is not address(0)"
        );
        TicketCollection storage ticketCollection = listTicketCollection[
            ticketCollectionAddress
        ];
        require(
            ticketCollection.status == TicketCollectionStatus.ACTIVE,
            "The ticket collection status is invalid"
        );
        TournamentDetail storage tournament = tournamentDetails[tournamentId];
        require(
            tournament.status == TournamentStatus.PENDING,
            "The tournament status is invalid"
        );
        tournament.tournamentId = tournamentId;
        tournament.ticketCollectionAddress = ticketCollectionAddress;
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

    // Deposit tickets to DGG SC
    function depositTicket(
        DepositTicketDetail[] memory depositTicketDetail
    ) public {
        for (uint256 i =0 ; i < depositTicketDetail.length; i++) {
                require(listTicketCollection[depositTicketDetail[i].ticketCollectionAddress].status == TicketCollectionStatus.ACTIVE, "The ticket collection status is invalid");
                for (uint256 x =0 ; x <  depositTicketDetail[i].tokenIds.length; x ++) {
                    depositTicketOfUser[msg.sender][depositTicketDetail[i].ticketCollectionAddress].push(depositTicketDetail[i].tokenIds[x]);
                    IERC721(depositTicketDetail[i].ticketCollectionAddress).transferFrom(msg.sender, address(this), depositTicketDetail[i].tokenIds[x]);
                
                }
            }

            emit DepositTicketEvent(depositTicketDetail);

    
    }
        
    function useTicket(
        address ticketCollectionAddress,
        uint256 tournamentId
    ) public {
        
        TournamentDetail memory tournament = tournamentDetails[tournamentId];
        require(
            tournament.status == TournamentStatus.OPEN,
            "The tournament is closed"
        );

        require(
            tournament.ticketCollectionAddress == ticketCollectionAddress,
            "It is an invalid ticket collection"
        );
        
        tournament.totalTickets += 1;
        uint256 length = depositTicketOfUser[msg.sender][ticketCollectionAddress].length;
        require(length > 0, "The number of tickets is not enough");
        uint256 tokenId = depositTicketOfUser[msg.sender][ticketCollectionAddress][length-1];
        NFT721Ticket(ticketCollectionAddress).burn(tokenId);
        depositTicketOfUser[msg.sender][ticketCollectionAddress].pop();
        TicketCollection storage ticketCollection = listTicketCollection[
            ticketCollectionAddress
        ];

        ticketRevenue[tournament.revenueAddress][
            ticketCollection.tokenBuy
        ] += ticketCollection.price;

        emit UseTicketEvent(ticketCollectionAddress, tournamentId);

    }

    function getValueRevenue(
        address revenueAddress,
        address tokenBuy
    ) public view returns (uint256) {
        uint256 value = ticketRevenue[revenueAddress][tokenBuy];
        return value;
    }

    function claimRevenueTicket(address token, uint256 amount) public {
        uint256 revenue = ticketRevenue[msg.sender][token];

        require(revenue > 0, "It is not enough revenue");
        require(amount > 0, "Amount must be greater than zero");
        require(amount < revenue, "The amount must be smaller than the available revenue");

        SafeERC20.safeTransfer(IERC20(token), msg.sender, amount);

        ticketRevenue[msg.sender][token] -= amount;

        emit ClaimRevenueTicketEvent(msg.sender, token, amount);
    }

    function getNumberOfTicket(
        address ticketCollectionAddress,
        address user
    ) public view returns (uint256) {
       
        return depositTicketOfUser[user][ticketCollectionAddress].length;
        
    }

    function getListTicketOfUser(
        address user
    ) public view returns (DepositTicketDetail[] memory) {
        DepositTicketDetail[] memory dpt = new DepositTicketDetail[](listTicketCollectionAddress.length);
        for(uint256 i =0 ; i < listTicketCollectionAddress.length; i++) { 
            
                dpt[i].ticketCollectionAddress = listTicketCollectionAddress[i];
                dpt[i].tokenIds = depositTicketOfUser[user][listTicketCollectionAddress[i]];
          
        }
        return dpt;
       
    }

    function changeOwnershipNFTContract(address ticketCollectionAddress,address _newOwner) external onlyAdmin() {
        NFT721Ticket(ticketCollectionAddress).transferOwnership(_newOwner);
    }

     function verify(
        uint256 requestId,
        bytes memory signature
    ) internal pure returns (address) {
        string memory numberAsString = uintToString(requestId);
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                uintToString(bytes(numberAsString).length),
                numberAsString
            )
        );
        return recoverSigner(ethSignedMessageHash, signature);
    }

    function recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(
        bytes memory sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function uintToString(
        uint256 _value
    ) public pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }


    function getListTicketCollectionAddress() public view returns(address[] memory) {
        return listTicketCollectionAddress;
    }


}

