// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./PermissionsEnumerable.sol";
import "./IMintableERC20.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./ERC721.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./INFTLottery.sol";
import "./ProtocolFee.sol";
import "./FixedPointMathLib.sol";
import "./FundVault.sol";

contract NFTLottery is INFTLottery, PermissionsEnumerable, ReentrancyGuard, ProtocolFee, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using FixedPointMathLib for uint256;

    uint256 public nextLotteryId;
    mapping(uint256 => Lottery) public lotteries;   // lotteryId => Lottery info
    mapping(uint256 => LotteryPlayers) public players;  // lotteryId => Players info

    FundVault fundVault;
    uint16 fundBps;          // The % of oversold goes to funds (Basis Points)

    mapping(uint256 => uint256) public rands;   // For transparency. Random number picked for each lottery

    address raffleToken;
    mapping(uint256 => mapping(address => bool)) public raffleTokenClaims; // mapping to store raffle token claims: lotteryId => wallet => didClaim
    mapping(uint256 => mapping(address => bool)) public refunds; // mapping to store refunds: lotteryId => wallet => didClaim


    // =============================================================
    //                    Modifiers
    // =============================================================
    modifier onlyLotteryOwnerOrAdmin(uint256 lotteryId) {
        require(msg.sender == lotteries[lotteryId].owner || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only the lottery owner or admin can open the lottery");
        _;
    }

    modifier onlyLotteryOwner(uint256 lotteryId) {
        require(msg.sender == lotteries[lotteryId].owner, "Only the lottery owner can open the lottery");
        _;
    }

    modifier whenLotteryPending(uint256 lotteryId) {
        require(lotteries[lotteryId].state == LotteryState.Pending, "Lottery is not pending"); 
        _;
    }

    modifier whenLotteryOpen(uint256 lotteryId) {
        require(lotteries[lotteryId].state == LotteryState.Open, "Lottery is not running"); 
        _;
    }

    modifier whenLotteryOpenOrPending(uint256 lotteryId) {
        require(lotteries[lotteryId].state == LotteryState.Pending || lotteries[lotteryId].state == LotteryState.Open, "Lottery is not pending nor open"); 
        _;
    }

    modifier nonExpired(uint256 lotteryId) {
        require(lotteries[lotteryId].endTimestamp == 0 || block.timestamp < lotteries[lotteryId].endTimestamp, "Lottery time end");
        _;
    }

    // =============================================================
    //                    Constructor
    // =============================================================
    constructor(address foundationWallet, address fundVaultAddress, address raffleTokenAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        nextLotteryId = 1;
        addFeeInfo(0, Fee(FeeType.Bps, 500, 0, foundationWallet)); 
        addFeeInfo(1, Fee(FeeType.Bps, 300, 0, foundationWallet)); 

        fundVault = FundVault(fundVaultAddress);
        fundBps = 2_000;    // 20%

        raffleToken = raffleTokenAddress;
    }

    // =============================================================
    //                    External calls
    // =============================================================
    function pause() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    function updateFundVault(address newFundVaultAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fundVault = FundVault(newFundVaultAddress);
    }   

    function updateCategory(uint256 lotteryId, uint8 newCategory) external onlyLotteryOwnerOrAdmin(lotteryId) {
        lotteries[lotteryId].category = newCategory;
    }

    function createLottery(Lottery calldata lotteryData) external virtual override returns (uint256 lotteryId) {
        require(lotteryData.minTickets > 0, "Min tickets Zero");

        lotteryId = nextLotteryId++;
        lotteries[lotteryId] = Lottery({
            owner: lotteryData.owner,
            salesRecipient: lotteryData.salesRecipient,
            nftAddress: lotteryData.nftAddress,
            tokenId: lotteryData.tokenId,
            ticketCurrency: lotteryData.ticketCurrency,
            ticketCost: lotteryData.ticketCost,
            minTickets: lotteryData.minTickets,
            category: lotteryData.category,
            startTimestamp: 0,
            endTimestamp: 0,
            state: LotteryState.Pending,
            winner: address(0)
        });

        IERC721 nftContract = IERC721(lotteryData.nftAddress);
        nftContract.safeTransferFrom(msg.sender, address(this), lotteryData.tokenId);

        emit LotteryCreated(lotteryId, lotteryData);

        // Open lottery directly. (Updated 2023/08/10)
        openLottery(lotteryId);
    }

    function openLottery(uint256 lotteryId) public virtual override onlyLotteryOwner(lotteryId) whenLotteryPending(lotteryId) {
        // Set the state of the lottery to Open
        lotteries[lotteryId].state = LotteryState.Open;
        lotteries[lotteryId].startTimestamp = block.timestamp;
        lotteries[lotteryId].endTimestamp = block.timestamp + 7 days;

        emit LotteryOpened(lotteryId, lotteries[lotteryId]);
    }

    function closeLottery(uint256 lotteryId) external virtual override onlyLotteryOwnerOrAdmin(lotteryId) whenLotteryOpenOrPending(lotteryId) nonReentrant {
        // Set the state of the lottery to Closed
        lotteries[lotteryId].state = LotteryState.Closed;
        lotteries[lotteryId].endTimestamp = block.timestamp;

        // Mininum ticket sale failed. 
        // Or there is no participant. Send the nft back to owner.
        if (players[lotteryId].totalTicketsSold < lotteries[lotteryId].minTickets || players[lotteryId].totalTicketsSold < 1) {
            _refundNFT(lotteryId);
        }
        // If there are participants, pick random winner.
        else {
            _pickWinner(lotteryId);
        }

        emit LotteryClosed(lotteryId, lotteries[lotteryId]);
    }

    function extendEndtime(uint256 lotteryId) external onlyLotteryOwnerOrAdmin(lotteryId) whenLotteryOpenOrPending(lotteryId) nonExpired(lotteryId) {
        lotteries[lotteryId].endTimestamp = block.timestamp + 7 days;
    }

    function buyTicket(uint256 lotteryId, uint256 numberOfTickets) public virtual override whenLotteryOpen(lotteryId) nonExpired(lotteryId) nonReentrant {
        require(numberOfTickets > 0 && numberOfTickets < type(uint256).max, "Invalid ticket count");
        IERC20(lotteries[lotteryId].ticketCurrency).safeTransferFrom(msg.sender, address(this), numberOfTickets.mul(lotteries[lotteryId].ticketCost));

        players[lotteryId].totalTicketsSold += numberOfTickets;
        players[lotteryId].tickets[msg.sender] += numberOfTickets;

        // NOTE: Push as many times as the number of tickets the player bought.
        //       This is to pick random winner efficiently since we don't use chainlink VRF, and need to iterate over all loops.
        //       This prevents to have loops that could exceed gas limit on the _pickWinner().
        //       Trade-off with more gas fee here.
        for (uint256 i = 0; i < numberOfTickets; i++) {
            players[lotteryId].playerWallets.push(msg.sender);
        }

        emit LotteryTicketBought(lotteryId, msg.sender, numberOfTickets);
    }
    
    function _refundNFT(uint256 lotteryId) internal virtual {
        IERC721 nftContract = IERC721(lotteries[lotteryId].nftAddress);
        nftContract.safeTransferFrom(address(this), lotteries[lotteryId].owner, lotteries[lotteryId].tokenId);
    }
    
    function withdrawRefund(uint256 lotteryId) external nonReentrant {
        // Get the lottery data
        Lottery memory lottery = lotteries[lotteryId];

        require(lottery.state == LotteryState.Closed, "Raffle not closed");
        require(players[lotteryId].totalTicketsSold < lotteries[lotteryId].minTickets, "Not refundable");
        require(refunds[lotteryId][msg.sender] == false, "Already claimed");

        // Set the refund claim flag
        refunds[lotteryId][msg.sender] = true;

        // Get the ERC20 token contract
        IERC20 token = IERC20(lottery.ticketCurrency);

        // Transfer the tokens back to the player
        uint256 tickets = players[lotteryId].tickets[msg.sender];
        uint256 refundAmount = tickets.mul(lottery.ticketCost);
        token.safeTransfer(msg.sender, refundAmount);

        emit LotteryRefund(lotteryId, msg.sender, lotteries[lotteryId], refundAmount);
    }

    function claimRaffleToken(uint256 lotteryId) external nonReentrant {
        // Get the lottery data
        Lottery memory lottery = lotteries[lotteryId];
        
        require(lottery.winner != msg.sender, "Winner cannot claim");
        require(lottery.state == LotteryState.Closed, "Raffle not closed");
        require(players[lotteryId].totalTicketsSold >= lotteries[lotteryId].minTickets, "Refunded raffle");
        require(raffleTokenClaims[lotteryId][msg.sender] == false, "Already claimed");

        // Set the $RFT claim flag
        raffleTokenClaims[lotteryId][msg.sender] = true;

        // Get the ERC20 token contract
        IMintableERC20 token = IMintableERC20(raffleToken);
        uint8 decimals = ERC20(raffleToken).decimals();

        // Mint raffle token to player based on the tickets bought (Because it is stable tokens)
        uint256 tickets = players[lotteryId].tickets[msg.sender];
        uint256 rftAmount = tickets.mul(10 ** decimals);
        token.mintTo(msg.sender, rftAmount);

        emit RaffleTokenClaim(lotteryId, msg.sender, lotteries[lotteryId], tickets);
    }

    function _pickWinner(uint256 lotteryId) internal virtual {
        Lottery memory lottery = lotteries[lotteryId];
        IERC721 nftContract = IERC721(lottery.nftAddress);

        address winner = _randomPlayer(lotteryId);
        lotteries[lotteryId].winner = winner;
        emit LotteryWinner(lotteryId, winner, lottery);

        // Send NFT to the winner.
        nftContract.safeTransferFrom(address(this), winner, lottery.tokenId);

        // Send tokens to the salesRecipient.
        IERC20 token = IERC20(lottery.ticketCurrency);
        uint256 minTicketSales = lotteries[lotteryId].minTickets * lotteries[lotteryId].ticketCost;

        uint256 minSalesFee = _chargeFee(token, 0, minTicketSales);
        token.safeTransfer(lottery.salesRecipient, minTicketSales.sub(minSalesFee));

        uint256 numberOfOversoldTickets = players[lotteryId].totalTicketsSold - lotteries[lotteryId].minTickets;
        if (numberOfOversoldTickets > 0) {
            uint256 overSales = numberOfOversoldTickets * lotteries[lotteryId].ticketCost;
            uint256 overSalesFee = _chargeFee(token, 1, overSales);

            // fundBps portion goes to vault
            uint256 totalOverSalesDistribution = overSales.sub(overSalesFee);
            uint256 toVault = totalOverSalesDistribution.mulDivDown(fundBps, MAX_BPS);
            token.safeTransfer(address(fundVault), toVault);

            // other goes to winner
            token.safeTransfer(winner, totalOverSalesDistribution.sub(toVault));
        }
        
        lotteries[lotteryId].state = LotteryState.Closed;
    }

    function _randomPlayer(uint256 lotteryId) internal virtual returns (address) {
        // Calculate the total number of tickets
        uint256 totalTickets = players[lotteryId].playerWallets.length;

        // Generate a random number between 0 and totalTickets
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, totalTickets))) % totalTickets;

        // Store random number to show transpancy of raffle
        rands[lotteryId] = randomIndex;
    
        return players[lotteryId].playerWallets[randomIndex];
    }

    // =============================================================
    //                    View functions
    // =============================================================
    function getTotalTicketsSold(uint256 lotteryId) external view returns (uint256) {
        return players[lotteryId].totalTicketsSold;
    }

    function getPlayerWallets(uint256 lotteryId) external view returns (address[] memory) {
        return players[lotteryId].playerWallets;
    }

    function getTickets(uint256 lotteryId, address player) external view returns (uint256) {
        return players[lotteryId].tickets[player];
    }

    function isPlayerOf(uint256 lotteryId, address participant) private view returns (bool) {
        for (uint256 i = 0; i < players[lotteryId].playerWallets.length; i++) {
            if (players[lotteryId].playerWallets[i] == participant) {
                return true;
            }
        }
        return false;
    }
    // =============================================================
    //                    Internal Hook logic
    // =============================================================
    function _canSetFeeInfo() internal view virtual override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // =============================================================
    //                    ERC721Receiver
    // =============================================================
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns(bytes4) {
        return this.onERC721Received.selector;
    }
}
