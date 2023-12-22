// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {Multicall} from "./Multicall.sol";
import {Pausable} from "./Pausable.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";

import "./BankV2.sol";

contract CoinTossV5 is
    VRFConsumerBaseV2,
    Ownable,
    Pausable,
    Multicall,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    BankV2 public bank;

    uint64 s_subscriptionId;

    VRFCoordinatorV2Interface COORDINATOR;

    address vrfCoordinator = 0x41034678D6C633D8a95c75e1138A360a28bA15d1;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    bytes32 keyHash = 0x68d24f9a037a649944964c2a1ebd0b2918f4a243d2a99701cc22b548cf2daff0;

    uint32 callbackGasLimit = 2500000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords = 2;

    uint256 public s_randomWords;
    uint256 public s_requestId;
    address public s_owner;

    /// @notice Emitted after the bank is set.
    /// @param bank Address of the bank contract.
    event SetBank(address bank);
    /// @notice Emitted after the house edge is set for a token.
    /// @param token Address of the token.
    /// @param houseEdge House edge rate.
    event SetHouseEdge(address indexed token, uint16 houseEdge);

    error ExcessiveHouseEdge();
    error ForbiddenToken();
    error WrongGasValueToCoverFee();
    error AccessDenied();
    error InvalidAddress();
    error TokenHasPendingBets();

    struct Token {
        uint16 houseEdge;
        uint64 pendingCount;
    }
    /// @notice Maps tokens addresses to token configuration.
    mapping(address => Token) public tokens;

    struct Bet {
        bool resolved;
        address payable user;
        address token;
        uint256 id;
        uint256 amount;
        uint256 blockTime;
        bool betStatus;
        // uint256 payout;
    }

    // Fee struct
    struct Fee {
        uint256 betAmountFee;
        uint256 ProfitFee;
    }

    /// @notice Maps bets IDs to Bet information.
    mapping(uint256 => Bet) public bets;

    /// @notice Maps users addrejsses to bets IDs
    mapping(address => uint256[]) internal _userBets;

    /// @notice Emitted after the bet amount is transfered to the user.
    /// @param id The bet ID.
    /// @param user Address of the gamer.
    /// @param amount Number of tokens refunded.
    /// @param chainlinkVRFCost The Chainlink VRF cost refunded to player.
    event BetRefunded(
        uint256 id,
        address user,
        uint256 amount,
        uint256 chainlinkVRFCost
    );

    /// @notice Insufficient bet amount.
    /// @param minBetAmount Bet amount.
    error UnderMinBetAmount(uint256 minBetAmount);

    /// @notice Bet isn't resolved yet.
    error NotFulfilled();

    /// @notice Bet provided doesn't exist or was already resolved.
    error NotPendingBet();

    // Coin toss
    /// @notice Full coin toss bet information struct.
    /// @param bet The Bet struct information.
    /// @param diceBet The Coin Toss bet struct information.
    /// @dev Used to package bet information for the front-end.
    struct FullCoinTossBet {
        Bet bet;
        CoinTossBet coinTossBet;
    }

    /// @notice Coin Toss bet information struct.
    /// @param face The chosen coin face.
    /// @param rolled The rolled coin face.
    struct CoinTossBet {
        bool face;
        bool rolled;
    }

    /// @notice Maps bets IDs to chosen and rolled coin faces.
    /// @dev Coin faces: true = Tails, false = Heads.
    mapping(uint256 => CoinTossBet) public coinTossBets;

    /// @notice Emitted after a bet is placed.
    /// @param id The bet ID.
    /// @param user Address of the gamer.
    /// @param token Address of the token.
    /// @param amount The bet amount.
    /// @param face The chosen coin face.
    event PlaceBet(
        uint256 id,
        address indexed user,
        address indexed token,
        uint256 amount,
        bool face
    );

    /// @notice Emitted after a bet is rolled.
    /// @param id The bet ID.
    /// @param user Address of the gamer.
    /// @param token Address of the token.
    /// @param amount The bet amount.
    /// @param face The chosen coin face.
    /// @param rolled The rolled coin face.
    event Roll(
        uint256 id,
        address indexed user,
        address indexed token,
        uint256 amount,
        bool face,
        bool rolled
        // uint256 payout
    );

    // Ends heref

    constructor(
        uint64 subscriptionId,
        address bankAddress
    ) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_owner = msg.sender;
        s_subscriptionId = subscriptionId;
        setBank(bankAddress);
    }

    /// @notice Returns whether the token has pending bets.
    /// @return Whether the token has pending bets.
    function hasPendingBets(address token) public view returns (bool) {
        return tokens[token].pendingCount != 0;
    }

    function setCallBackLimit (uint32 amount) external onlyOwner {
        callbackGasLimit = amount;
    }

    function _getFees(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        return (tokens[token].houseEdge * amount) / 10000;
    }

    /// @notice Sets the Bank contract.
    /// @param _bank Address of the Bank contract.
    function setBank(address _bank) public onlyOwner {
        if (address(_bank) == address(0)) {
            // revert InvalidAddress();
            // return false;
        }
        bank = BankV2(_bank);
        emit SetBank(address(_bank));
    }

    /// @notice Sets the game house edge rate for a specific token.
    /// @param token Address of the token.
    /// @param houseEdge House edge rate.
    /// @dev The house edge rate couldn't exceed 4%.
    function setHouseEdge(address token, uint16 houseEdge) external onlyOwner {
        if (houseEdge > 400) {
            revert ExcessiveHouseEdge();
        }
        if (hasPendingBets(token)) {
            revert TokenHasPendingBets();
        }
        tokens[token].houseEdge = houseEdge;
        emit SetHouseEdge(token, houseEdge);
    }

    /// @notice Check if the token has the 0x address.
    /// @param token Address of the token.
    /// @return Whether the token's address is the 0x address.
    function _isGasToken(address token) private pure returns (bool) {
        return token == address(0);
    }

    function sendToTreasury(address currency, uint256 amount) internal {
        if (amount == 0 || currency == address(0)) return;
        IERC20(currency).transferFrom(msg.sender, bank.treasury(), amount);
    }


    function _newBet(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 multi
    ) internal whenNotPaused nonReentrant returns (Bet memory) {
        Token storage token = tokens[tokenAddress];
        require(bank.isAllowedToken(tokenAddress) == true, "!Token");
        require(token.houseEdge > 0, "!Token House Edge");

        address user = msg.sender;
        bool isGasToken = tokenAddress == address(0);
        uint256 betAmount = tokenAmount;

        {
            uint256 minBetAmount = bank.getMinBetAmount(tokenAddress);
            if (betAmount < minBetAmount) {
                revert UnderMinBetAmount(minBetAmount);
            }

            uint256 maxBetAmount = bank.getMaxBetAmount(tokenAddress, multi);
            if (betAmount > maxBetAmount) {
                if (isGasToken) {
                    payable(user).transfer(betAmount - maxBetAmount);
                }
                betAmount = maxBetAmount;
            }
        }


        s_requestId = COORDINATOR.requestRandomWords( 
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        Bet memory newBet = Bet(
            false,
            payable(user),
            tokenAddress,
            s_requestId,
            betAmount,
            block.timestamp,
            false
            // 0
        );
        _userBets[user].push(s_requestId);
        bets[s_requestId] = newBet;

        // If ERC20, transfer the tokens
        if (!isGasToken) {
            sendToTreasury(tokenAddress, betAmount);
        }

        return newBet;
    }

    uint256 public multiplier = 3;

    function updateMultiplier(uint256 amount) external onlyOwner {
        multiplier = amount;
    }

    function getMultiplier() private view returns (uint256) {
        return multiplier;
    }

    /// @notice Gets the list of the last user bets.
    /// @param user Address of the gamer.
    /// @param dataLength The amount of bets to return.
    /// @return A list of Bet.
    function _getLastUserBets(
        address user,
        uint256 dataLength
    ) internal view returns (Bet[] memory) {
        uint256[] memory userBetsIds = _userBets[user];
        uint256 betsLength = userBetsIds.length;

        if (betsLength < dataLength) {
            dataLength = betsLength;
        }

        Bet[] memory userBets = new Bet[](dataLength);
        if (dataLength != 0) {
            uint256 userBetsIndex;
            for (uint256 i = betsLength; i > betsLength - dataLength; i--) {
                userBets[userBetsIndex] = bets[userBetsIds[i - 1]];
                userBetsIndex++;
            }
        }

        return userBets;
    }

    function getBetData(uint256 id) public view returns (Bet memory betData) {
        Bet storage data = bets[id];
        return data;
    }

    function getBetStatus(uint256 id) public view returns (bool status) {
        Bet storage data = bets[id];
        return data.betStatus;
    }

    /// @notice Refunds the bet to the user if the Chainlink VRF callback failed.
    /// @param id The Bet ID.
    function refundBet(uint256 id) external nonReentrant onlyOwner {
        Bet storage bet = bets[id];
        if (bet.resolved == true) {
            revert NotPendingBet();
        } else if (block.timestamp < bet.blockTime + 30) {
            revert NotFulfilled();
        }

        Token storage token = tokens[bet.token];
        token.pendingCount--;

        bet.resolved = true;
        // bet.payout = bet.amount;

        if (bet.token == address(0)) {
            payable(bet.user).transfer(bet.amount);
        } else {
            IERC20(bet.token).safeTransfer(bet.user, bet.amount);
        }
    }

    // Coin toss start here
    /// @notice Calculates the target payout amount.
    /// @param betAmount Bet amount.
    /// @return The target payout amount.
    function _getPayout(uint256 betAmount) private view returns (uint256) {
        return betAmount * multiplier;
    }


    /// @notice Creates a new bet and stores the chosen coin face.
    /// @param face The chosen color number from the struct .
    /// @param token Address of the token.
    /// @param tokenAmount The number of tokens bet.
    function wager(
        bool face,
        address token,
        uint256 tokenAmount
    ) external payable whenNotPaused {
        Bet memory bet = _newBet(token, tokenAmount, _getPayout(10000));

        coinTossBets[bet.id].face = face;

        emit PlaceBet(bet.id, bet.user, bet.token, bet.amount, face);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Gets the token's balance.
    /// The token's house edge allocation amounts are subtracted from the balance.
    /// @param token Address of the token.
    /// @return The amount of token available for profits.
    function getTokenBalance(address token) public view returns (uint256) {
        uint256 tokenBal;
        if (_isGasToken(token)) {
            return tokenBal = address(this).balance;
        } else {
            return tokenBal = IERC20(token).balanceOf(address(this));
        }
    }

    function fulfillRandomWords(
        uint256 id /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        CoinTossBet storage coinTossBet = coinTossBets[id];
        Bet storage bet = bets[id];
        uint256 roller = randomWords[0] % 2;

        bool[2] memory coinSides = [false, true];
        bool rolledCoinSide = coinSides[roller];
        coinTossBet.rolled = rolledCoinSide;

        if (rolledCoinSide == coinTossBet.face) {
            bet.resolved = true;
            bet.betStatus = true;
            address token = bet.token;
            address payable user = bet.user;
            uint256 betAmount = bet.amount;

            // processPayouts(bet, bet.betStatus, _getPayout(bet.amount));

            uint256 payout = _getPayout(betAmount);
            uint256 profit = payout;

            uint256 profitFee = _getFees(token, betAmount);

            uint256 profitPayout = profit - profitFee;

            // Transfer the payout from the bank, the bet amount fee to the bank, and account fees.
            bank.payout(user, token, profitPayout, profitFee);
            bank.updatePoolInterest(profitPayout,token,true);

        } else {
            bet.resolved = true;
            bet.betStatus = false;
        }

        emit Roll(
            bet.id,
            bet.user,
            bet.token,
            bet.amount,
            coinTossBet.face,
            rolledCoinSide
            // payout
        );
    }

    /// @notice Pauses the contract to disable new bets.
    function pause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /// @notice Gets the list of the last user bets.
    /// @param user Address of the gamer.
    /// @param dataLength The amount of bets to return.
    /// @return A list of Coin Toss bet.
    function getLastUserBets(
        address user,
        uint256 dataLength
    ) external view returns (FullCoinTossBet[] memory) {
        Bet[] memory lastBets = _getLastUserBets(user, dataLength);
        FullCoinTossBet[] memory lastCoinTossBets = new FullCoinTossBet[](
            lastBets.length
        );
        for (uint256 i; i < lastBets.length; i++) {
            lastCoinTossBets[i] = FullCoinTossBet(
                lastBets[i],
                coinTossBets[lastBets[i].id]
            );
        }
        return lastCoinTossBets;
    }
}

