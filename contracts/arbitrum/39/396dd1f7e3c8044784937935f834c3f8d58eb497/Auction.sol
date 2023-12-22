pragma solidity ^0.8.0;

import "./PricingSession.sol";
import "./ABCTreasury.sol";
import "./ReentrancyGuard.sol";


///@author Medici
///@title Bounty auction contract for Abacus
contract BountyAuction is ReentrancyGuard {

    /// @notice store pricing session address 
    PricingSession public session;

    /// @notice store treasury address
    ABCTreasury public treasury;

    /* ======== ADDRESS ======== */

    /// @notice store contract admin address
    address public admin;

    /// @notice store ABC token contract
    address public ABCToken;

    /* ======== BOOL ======== */

    /// @notice track auction active status 
    bool public auctionStatus;

    /// @notice used for customizable first session timeline
    bool public firstSession;

    /* ======== UINT ======== */

    /// @notice used to map to current bounty auction
    uint public nonce;

    /* ======== MAPPINGS ======== */

    /*//////////////////////////////
    //     PER AUCTION STORAGE    //
    //////////////////////////////*/

    /// @notice maps the auction nonce to it's highest bid value
    mapping(uint => uint) public highestBid;
    
    /// @notice maps the auction nonce to it's highest bidder
    mapping(uint => address) public highestBidder;

    /// @notice maps the auction nonce to it's end timestamp
    mapping(uint => uint) public endTime;
    
    /// @notice maps the auction nonce to it's winner
    mapping(uint => address) public winners;
    
    /// @notice maps the action to all it's votes mapped to the voter
    mapping(uint => mapping(address => AuctionVote)) public userVote;

    /*//////////////////////////////
    //     PER ACCOUNT STORAGE    //
    //////////////////////////////*/

    mapping(address => uint) bidTime;

    mapping(address => uint) tvl;

    /* ======== STRUCTS ======== */

    /// @notice stores bidders core information
    struct AuctionVote {

        address nftAddress;
        uint tokenid;
        uint intitialAppraisal;
        uint bid;
    }

    /* ======== EVENTS ======== */
    event newBidSubmitted(address _bidder, uint _bidAmount, address _nftAddress, uint _tokenid, uint _initialAppraisal);
    event auctionEnded(address _highestBidder, uint _highestBid, address _nftAddress, uint _tokenid, uint _initialAppraisal);

    /* ======== Constructor ======== */

    constructor() {
        
        /// @notice set contract admin
        admin = msg.sender;

        /// @notice set session account status to signify auction is active
        auctionStatus = true;
    }

    /* ======== ADMIN ======== */
    
    ///@notice toggles active status of Auction contract
    function toggleAuction() external {
        require(msg.sender == admin);
        auctionStatus = !auctionStatus;
        nonce++;
    }

    /// @notice set session contract to be stored
    /// @param _session address of desired Pricing Session principle contract
    function setSessionContract(address _session) external {
        require(msg.sender == admin);
        session = PricingSession(payable(_session));
    }

    /// @notice set treasury contract to be stored
    /// @param _treasury address of desired ABC treasury address
    function setTreasury(address _treasury) external {
        require(msg.sender == admin);
        treasury = ABCTreasury(payable(_treasury));
    }

    /// @notice set token contract to be stored
    /// @param _token address of desired ABC token contract
    function setToken(address _token) external {
        require(msg.sender == admin);
        ABCToken = _token;
    }

    /// @notice change the state of first session once first auction is complete
    /// @param _state bool representative of whether or not we're currently in the first session
    function setFirst(bool _state) external {
        require(msg.sender == admin);
        firstSession = _state;
    }

    /* ======== AUCTION INTERACTION ======== */

    /// @notice allow user to submit new bid
    /// @param _nftAddress - address of the ERC721/ERC1155 token
    /// @param _tokenid - ID of the token
    /// @param _initialAppraisal - initial nft appraisal 
    function newBid(address _nftAddress, uint _tokenid, uint _initialAppraisal) nonReentrant payable external {
        require(
            msg.value > highestBid[nonce]
            && auctionStatus
            && (session.nftNonce(_nftAddress,_tokenid) == 0 || session.getStatus(_nftAddress, _tokenid) == 5)
        );
        bidTime[msg.sender] = block.timestamp;
        highestBidder[nonce] = msg.sender;
        highestBid[nonce] = msg.value;
        tvl[msg.sender] -= userVote[nonce][msg.sender].bid;
        (bool sent, ) = payable(msg.sender).call{value: userVote[nonce][msg.sender].bid}("");
        require(sent);
        userVote[nonce][msg.sender].nftAddress = _nftAddress;
        userVote[nonce][msg.sender].tokenid = _tokenid;
        userVote[nonce][msg.sender].intitialAppraisal = _initialAppraisal;
        userVote[nonce][msg.sender].bid = msg.value;
        tvl[msg.sender] += msg.value;
        emit newBidSubmitted(msg.sender, msg.value, _nftAddress, _tokenid, _initialAppraisal);
    }

    /// @notice allow add to past bid
    /// @param _nftAddress - address of the ERC721/ERC1155 token
    /// @param _tokenid - ID of the token
    function addToBid(address _nftAddress, uint _tokenid) nonReentrant payable external {
        require(
            userVote[nonce][msg.sender].bid + msg.value > highestBid[nonce] 
            && auctionStatus
            && (session.nftNonce(_nftAddress,_tokenid) == 0 || session.getStatus(_nftAddress, _tokenid) == 5)
        );
        userVote[nonce][msg.sender].bid += msg.value;
        highestBidder[nonce] = msg.sender;
        highestBid[nonce] = userVote[nonce][msg.sender].bid;
        tvl[msg.sender] += msg.value;
    }

    /// @notice allow user to change nft that they'd like appraised if they win
    /// @param _nftAddress users desired NFT address for session to be created
    /// @param _tokenid users desired tokenid for session to be created
    /// @param _initialAppraisal users desired initial appraisal value for session to be created
    function changeInfo(address _nftAddress, uint _tokenid, uint _initialAppraisal) external {
        require(userVote[nonce][msg.sender].nftAddress != address(0) && auctionStatus);
        userVote[nonce][msg.sender].nftAddress = _nftAddress;
        userVote[nonce][msg.sender].tokenid = _tokenid;
        userVote[nonce][msg.sender].intitialAppraisal = _initialAppraisal;
    }

    /// @notice triggered when auction ends, starts session for highest bidder
    function endAuction() nonReentrant external {
        if(firstSession) {
            require(msg.sender == admin);
        }
        require(endTime[nonce] < block.timestamp && auctionStatus);
        uint bountySend = userVote[nonce][highestBidder[nonce]].bid;
        tvl[highestBidder[nonce]] -= bountySend;
        session.createNewSession{value: bountySend}(
            userVote[nonce][highestBidder[nonce]].nftAddress, 
            userVote[nonce][highestBidder[nonce]].tokenid,
            userVote[nonce][highestBidder[nonce]].intitialAppraisal,
            86400
        );
        userVote[nonce][highestBidder[nonce]].bid = 0;
        endTime[++nonce] = block.timestamp + 86400;
        emit auctionEnded(
            highestBidder[nonce], 
            userVote[nonce][highestBidder[nonce]].bid, 
            userVote[nonce][highestBidder[nonce]].nftAddress, 
            userVote[nonce][highestBidder[nonce]].tokenid, 
            userVote[nonce][highestBidder[nonce]].intitialAppraisal
        );
    }

    /// @notice allows users to claim non-employed funds
    function claim() nonReentrant external {
        uint returnValue;
        if(highestBidder[nonce] != msg.sender) {
            returnValue = tvl[msg.sender];
            userVote[nonce][msg.sender].bid = 0;
        }
        else {
            returnValue = tvl[msg.sender] - userVote[nonce][msg.sender].bid;
        }
        tvl[msg.sender] -= returnValue;
        (bool sent, ) = payable(msg.sender).call{value: returnValue}("");
        require(sent);
    }
}
