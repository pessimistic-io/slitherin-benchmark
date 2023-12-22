// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC721} from "./ERC721.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

interface IRandomizer {
    function request(
        uint256 _callbackGasLimit,
        uint256 _confirmations
    ) external returns (uint256);

    function clientWithdrawTo(address _to, uint256 _amount) external;
}

/**
 * @title PowerPlayLottery is a Contract for a lottery where players pick 6 distinct numbers from 1-47 and get prizes depending of how many numbers they match with the random numbers
 * @notice
 */
contract MoneyGame is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //Lottery Constants
    uint8 constant POWER_PLAY_MULTIPLIER_COST = 5;
    uint256 constant MAX_NUM_TICKETS = 5368786;
    uint256 constant MAX_TICKETS_BOUGHT = 100;
    uint256 constant MAX_TICKETS_REDEEMED = 100;

    address public immutable prizeTokenAddress;
    address public immutable randomizerAddress;
    address public immutable DAOAddress;
    address public immutable owner;

    uint256[] public LotteryNumbers;
    uint256[4] public prizes;
    uint256[4] public powerPlayPrizes;
    uint256 public immutable ticketCost;
    uint256 public immutable lotteryDuration;

    uint256 randomizerGasLimit = 2_000_000;
    uint256 randomizerConfirmations = 5;

    string public baseURI;
    //Enum and Structs
    enum LotteryStatus {
        NOT_STARTED,
        ON_GOING,
        AWAITING_VRF
    }

    struct Lottery {
        mapping(bytes32 => uint256) ticketCount;
        mapping(uint256 => uint8[6][]) tickets;
        mapping(uint256 => uint8[6][]) powerPlayTickets;
        uint256 drawTime;
        uint8[6] result;
        uint256 numberOfJackpots;
        uint256 jackPotPrize;
        uint256 VRFRequestID;
        uint256 totalTickets;
    }

    struct VRFRequest {
        uint256 id;
        uint256 blockNumber;
        uint256 lotteryId;
    }

    //Lottery data storage
    LotteryStatus public currentStatus;
    VRFRequest public currentVRFRequest;

    mapping(uint256 => Lottery) public lotteries;

    uint256 public currentJackPot;
    uint256 public pendingWithdrawJackpotValue;

    uint256 public lotteryCounter;

    uint256 private _tokenIds;
    bool public pauseLottery;

    constructor(
        address _prizeTokenAddress,
        address _randomizerAddress,
        address _DAOAddress,
        address _owner,
        uint256[4] memory _prizes,
        uint256[4] memory _powerPlayPrizes,
        uint256 _ticketCost,
        uint256 _lotteryDuration
    ) ERC721("MoneyGame", "$MoneyG") {
        prizeTokenAddress = _prizeTokenAddress;
        randomizerAddress = _randomizerAddress;
        DAOAddress = _DAOAddress;
        owner = _owner;
        prizes = _prizes;
        powerPlayPrizes = _powerPlayPrizes;
        ticketCost = _ticketCost;
        lotteryDuration = _lotteryDuration;
        for (uint256 i = 0; i < 47; i++) {
            LotteryNumbers.push(i + 1);
        }
    }

    /**
     * @dev Event emitted whenever a player buys a ticket
     * @param player address of the player
     * @param tokenId id of the NFT that holds the tickets
     * @param lotteryId id of the lottery for which the tickets were bought
     * @param numbers numbers selected by the player
     * @param isPowerPlay if each ticket includes powerPlay
     */
    event TicketsBought(
        address indexed player,
        uint256 indexed tokenId,
        uint256 lotteryId,
        uint8[6][] numbers,
        bool[] isPowerPlay
    );
    /**
     * @dev Event emitted whenever a player claims a ticket prize
     * @param player address of the player that claimed the reward
     * @param tokenId id of the NFT that held the tickets
     * @param lotteryId id of the lottery for which the rewards were claimed
     * @param amountClaimed prize amount given to the player
     */
    event RewardClaimed(
        address indexed player,
        uint256 indexed tokenId,
        uint256 lotteryId,
        uint256 amountClaimed
    );
    /**
     * @dev Event emitted when VRF draws the lottery numbers
     * @param lotteryId id of the lottery for which the numbers were drawn
     * @param numbers numbers drawn
     * @param numberOfJackpots number of jackpot prizes in this lottery
     */
    event NumbersDrawn(
        uint256 indexed lotteryId,
        uint8[6] numbers,
        uint256 numberOfJackpots
    );

    error MismatchedLength();
    error InavalidState(LotteryStatus have, LotteryStatus want);
    error NotDrawTime(uint256 have, uint256 want);
    error InvalidTicketOrder();
    error NotNFTOwner(address want, address have);
    error InvalidLength(uint256 max, uint256 have);
    error OnlyRandomizerCanFulfill(address have, address want);
    error InvalidNumber();
    error InvalidNumberOrder();
    error InvalidRequest();
    error LotteryNotFinished();
    error MaxTicketsSold();
    error InsufficientFunds(uint256 want, uint256 have);
    error InsufficientTime(uint256 current, uint256 have);

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Function to view tickets held by a NFT for a given lottery
     * @param tokenId id to the NFT
     * @param lotteryId id of the Lottery
     * @return tickets tickets held by the NFT
     * @return powerPlayTickets powerplay tickets held by the NFT
     */
    function getTicketsForLottery(
        uint256 tokenId,
        uint256 lotteryId
    ) external view returns (uint8[6][] memory, uint8[6][] memory) {
        return (
            lotteries[lotteryId].tickets[tokenId],
            lotteries[lotteryId].powerPlayTickets[tokenId]
        );
    }

    /**
     * @dev Function to view the VRF selected numbers for a given lottery
     * @param lotteryId id of the Lottery
     */
    function getLotteryResult(
        uint256 lotteryId
    ) external view returns (uint8[6] memory) {
        return lotteries[lotteryId].result;
    }

    /**
     * @dev Function to enter Lottery using an NFT, msg sender must be the owner of the NFT
     * @param tokenId id of the NFT
     * @param numbers numbers to get on lottery ticket, must be in order from lowest to highest and between 1 and 47, no repeated numbers allowed
     * @param isPowerPlay for each ticket if there should be powerPlay applied
     */
    function enterLottery(
        uint256 tokenId,
        uint8[6][] calldata numbers,
        bool[] calldata isPowerPlay
    ) external nonReentrant {
        if (currentStatus != LotteryStatus.ON_GOING) {
            revert InavalidState(currentStatus, LotteryStatus.ON_GOING);
        }
        if (numbers.length != isPowerPlay.length) {
            revert MismatchedLength();
        }
        if (numbers.length > MAX_TICKETS_BOUGHT || numbers.length == 0) {
            revert InvalidLength(MAX_TICKETS_BOUGHT + 1, numbers.length);
        }
        if (ownerOf(tokenId) != msg.sender) {
            revert NotNFTOwner(ownerOf(tokenId), msg.sender);
        }

        Lottery storage lottery = lotteries[lotteryCounter];
        if (lottery.totalTickets + numbers.length > MAX_NUM_TICKETS) {
            revert MaxTicketsSold();
        }
        uint256 totalFee;
        uint256 jackPotIncreaseAmount;
        for (uint256 i = 0; i < numbers.length; i++) {
            _checkLotteryNumbers(numbers[i]);

            lottery.ticketCount[keccak256(abi.encode(numbers[i]))] += 1;
            if (isPowerPlay[i]) {
                lottery.powerPlayTickets[tokenId].push(numbers[i]);
                totalFee += ticketCost * POWER_PLAY_MULTIPLIER_COST;
                jackPotIncreaseAmount +=
                    (ticketCost * POWER_PLAY_MULTIPLIER_COST) /
                    10;
            } else {
                lottery.tickets[tokenId].push(numbers[i]);
                totalFee += ticketCost;
                jackPotIncreaseAmount += (ticketCost) / 2;
            }
        }
        lottery.totalTickets += numbers.length;
        currentJackPot += jackPotIncreaseAmount;
        IERC20(prizeTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            totalFee
        );

        emit TicketsBought(
            msg.sender,
            tokenId,
            lotteryCounter,
            numbers,
            isPowerPlay
        );
    }

    /**
     * @dev Function to mint a NFT to hold the lottery tickets
     * @param numbers numbers to get on lottery ticket, must be in order from lowest to highest and between 1 and 47, no repeated numbers allowed
     * @param isPowerPlay for each ticket if there should be powerPlay applied
     */
    function mintNFTAndEnterLottery(
        uint8[6][] calldata numbers,
        bool[] calldata isPowerPlay
    ) external nonReentrant {
        if (currentStatus != LotteryStatus.ON_GOING) {
            revert InavalidState(currentStatus, LotteryStatus.ON_GOING);
        }
        if (numbers.length != isPowerPlay.length) {
            revert MismatchedLength();
        }
        if (numbers.length > MAX_TICKETS_BOUGHT || numbers.length == 0) {
            revert InvalidLength(MAX_TICKETS_BOUGHT + 1, numbers.length);
        }

        uint256 tokenId = _tokenIds;

        _mint(msg.sender, tokenId);

        Lottery storage lottery = lotteries[lotteryCounter];
        if (lottery.totalTickets + numbers.length > MAX_NUM_TICKETS) {
            revert MaxTicketsSold();
        }

        uint256 totalFee;
        uint256 jackPotIncreaseAmount;
        for (uint256 i = 0; i < numbers.length; i++) {
            _checkLotteryNumbers(numbers[i]);

            lottery.ticketCount[keccak256(abi.encode(numbers[i]))] += 1;
            if (isPowerPlay[i]) {
                lottery.powerPlayTickets[tokenId].push(numbers[i]);

                totalFee += ticketCost * POWER_PLAY_MULTIPLIER_COST;
                jackPotIncreaseAmount +=
                    (ticketCost * POWER_PLAY_MULTIPLIER_COST) /
                    10;
            } else {
                lottery.tickets[tokenId].push(numbers[i]);

                totalFee += ticketCost;
                jackPotIncreaseAmount += (ticketCost) / 2;
            }
        }
        currentJackPot += jackPotIncreaseAmount;
        lottery.totalTickets += numbers.length;

        IERC20(prizeTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            totalFee
        );

        _tokenIds++;

        emit TicketsBought(
            msg.sender,
            tokenId,
            lotteryCounter,
            numbers,
            isPowerPlay
        );
    }

    /**
     * @dev Function for players to claim prizes.
     * @param tokenId id of the NFT which holds the tickets, msg sender must be the owner of the NFT
     * @param lotteryId id of the lottery player which to claim the prizes for
     * @param tickets number of the tickets that are to be claimed, must be ordered from highest to lower
     * @param powerPlayTickets number of the powerplay tickets that are to be claimed, must be ordered from highest to lower
     */
    function claimReward(
        uint256 tokenId,
        uint256 lotteryId,
        uint256[] calldata tickets,
        uint256[] calldata powerPlayTickets
    ) external nonReentrant {
        if (tickets.length + powerPlayTickets.length > MAX_TICKETS_REDEEMED) {
            revert InvalidLength(
                MAX_TICKETS_REDEEMED + 1,
                tickets.length + powerPlayTickets.length
            );
        }
        if (ownerOf(tokenId) != msg.sender) {
            revert NotNFTOwner(ownerOf(tokenId), msg.sender);
        }
        Lottery storage lottery = lotteries[lotteryId];
        if (lottery.result[0] == 0) {
            revert LotteryNotFinished();
        }
        uint256 prizeAmount;

        for (uint i = 0; i < tickets.length; i++) {
            if (tickets.length > 1) {
                if (i <= tickets.length - 2) {
                    if (tickets[i] <= tickets[i + 1]) {
                        revert InvalidTicketOrder();
                    }
                }
            }
            uint256 numberOfMatches = _checkNumberOfMatches(
                lottery.tickets[tokenId][tickets[i]],
                lottery.result
            );

            if (numberOfMatches == 6) {
                prizeAmount += lottery.jackPotPrize / lottery.numberOfJackpots;
                pendingWithdrawJackpotValue -=
                    lottery.jackPotPrize /
                    lottery.numberOfJackpots;
            } else if (numberOfMatches >= 2) {
                prizeAmount += prizes[numberOfMatches - 2];
            }
            lottery.tickets[tokenId][tickets[i]] = lottery.tickets[tokenId][
                lottery.tickets[tokenId].length - 1
            ];
            lottery.tickets[tokenId].pop();
        }

        for (uint i = 0; i < powerPlayTickets.length; i++) {
            if (powerPlayTickets.length > 1) {
                if (i <= powerPlayTickets.length - 2) {
                    if (powerPlayTickets[i] <= powerPlayTickets[i + 1]) {
                        revert InvalidTicketOrder();
                    }
                }
            }
            uint256 numberOfMatches = _checkNumberOfMatches(
                lottery.powerPlayTickets[tokenId][powerPlayTickets[i]],
                lottery.result
            );

            lottery.powerPlayTickets[tokenId][powerPlayTickets[i]] = lottery
                .powerPlayTickets[tokenId][
                    lottery.powerPlayTickets[tokenId].length - 1
                ];
            lottery.powerPlayTickets[tokenId].pop();

            if (numberOfMatches == 6) {
                prizeAmount += lottery.jackPotPrize / lottery.numberOfJackpots;
                pendingWithdrawJackpotValue -=
                    lottery.jackPotPrize /
                    lottery.numberOfJackpots;
            } else if (numberOfMatches >= 2) {
                prizeAmount += powerPlayPrizes[numberOfMatches - 2];
            }
        }

        uint256 DAOFee = (prizeAmount * 5) / 100;
        IERC20(prizeTokenAddress).safeTransfer(
            msg.sender,
            prizeAmount - DAOFee
        );
        IERC20(prizeTokenAddress).safeTransfer(DAOAddress, DAOFee);

        emit RewardClaimed(msg.sender, tokenId, lotteryId, prizeAmount);
    }

    /**
     * @dev Function to start Lottery. It is used to start after lottery was paused and to set the jackpot prize after jackpot is given.
     * @param jackPotPrize amount of jackpot prize to set, pass 0 in order to not change the value
     */
    function startLottery(uint256 jackPotPrize) external onlyOwner {
        if (currentStatus != LotteryStatus.NOT_STARTED) {
            revert InavalidState(currentStatus, LotteryStatus.NOT_STARTED);
        }
        if (jackPotPrize != 0) {
            currentJackPot = jackPotPrize;
        }
        if (
            IERC20(prizeTokenAddress).balanceOf(address(this)) <
            currentJackPot + pendingWithdrawJackpotValue
        ) {
            revert InsufficientFunds(
                currentJackPot,
                IERC20(prizeTokenAddress).balanceOf(address(this))
            );
        }
        pauseLottery = false;
        currentStatus = LotteryStatus.ON_GOING;
        lotteryCounter++;
        lotteries[lotteryCounter].drawTime = block.timestamp + lotteryDuration;
    }

    /**
     * @dev Function to pause and unpause lottery, only callable by owner.
     */
    function togglePauseLottery() external onlyOwner {
        pauseLottery = !pauseLottery;
    }

    /**
     * @dev Function to withdraw funds from the VRF.
     * @param to to
     * @param amount amount
     */
    function whithdrawVRF(address to, uint256 amount) external onlyOwner {
        IRandomizer(randomizerAddress).clientWithdrawTo(to, amount);
    }

    /**
     * @dev Function to remove funds from contract in case of upgrade to new contract. Only callable by owner, last lottery must have started at least
     *  7 days before this function can be called so that players can claim their rewards.
     * @param to address to remove to
     * @param amount amount of token to remove
     * @param tokenAddress address of token to remove
     */
    function removeFunds(
        address to,
        uint256 amount,
        address tokenAddress
    ) external onlyOwner {
        if (
            block.timestamp < lotteries[lotteryCounter].drawTime + 3600 * 24 * 7
        ) {
            revert InsufficientTime(
                block.timestamp,
                lotteries[lotteryCounter].drawTime + 3600 * 24 * 7
            );
        }
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    /**
     * @dev Function to request random numbers from Randomizer VRF, lottery must be ongoing and block time must be greater than draw time.
     * Calling this function will change lottery status to AWAITING VRF, disabling ticket sales.
     */
    function drawRandomNumbers() external {
        if (currentStatus != LotteryStatus.ON_GOING) {
            revert InavalidState(currentStatus, LotteryStatus.ON_GOING);
        }
        if (block.timestamp < lotteries[lotteryCounter].drawTime) {
            revert NotDrawTime(
                block.timestamp,
                lotteries[lotteryCounter].drawTime
            );
        }
        uint256 requestId = _requestRandomNumbers();
        lotteries[lotteryCounter].VRFRequestID = requestId;
        currentStatus = LotteryStatus.AWAITING_VRF;

        currentVRFRequest = VRFRequest(requestId, block.number, lotteryCounter);
    }

    /**
     * @dev Function to redraw random numbers in case of callback no being called, will overwrite the previous request.
     *  Must wait 100 L1 blocks from previous request before being able to call.
     */
    function redrawRandomNumbers() external {
        if (currentStatus != LotteryStatus.AWAITING_VRF) {
            revert InavalidState(currentStatus, LotteryStatus.AWAITING_VRF);
        }
        if (block.number < currentVRFRequest.blockNumber + 100) {
            //100 mainnet blocks
            revert InsufficientTime(
                block.number,
                currentVRFRequest.blockNumber + 100
            );
        }
        uint256 requestId = _requestRandomNumbers();
        lotteries[lotteryCounter].VRFRequestID = requestId;
        currentVRFRequest = VRFRequest(requestId, block.number, lotteryCounter);
    }

    /**
     *
     * @param uri uri to set
     */
    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
    }

    function setVRFParameters(
        uint256 _limit,
        uint256 _confirmations
    ) external onlyOwner {
        randomizerGasLimit = _limit;
        randomizerConfirmations = _confirmations;
    }

    /**
     * @dev Function called by randomizer VRF
     * @param _id id of the VRF request
     * @param _value random number provided
     */
    function randomizerCallback(uint256 _id, bytes32 _value) external {
        //Callback can only be called by randomizer
        if (msg.sender != randomizerAddress) {
            revert OnlyRandomizerCanFulfill(msg.sender, randomizerAddress);
        }
        if (
            currentVRFRequest.id != _id ||
            currentVRFRequest.lotteryId != lotteryCounter
        ) {
            revert InvalidRequest();
        }
        delete (currentVRFRequest);
        Lottery storage lottery = lotteries[lotteryCounter];

        uint256[] memory numbersAvailable = LotteryNumbers;
        uint8[6] memory numbersDrawn;
        for (uint256 i = 0; i < 6; i++) {
            uint256 positionPicked = uint256(keccak256(abi.encode(_value, i))) %
                numbersAvailable.length;

            numbersDrawn[i] = uint8(numbersAvailable[positionPicked]);

            numbersAvailable[positionPicked] = numbersAvailable[
                numbersAvailable.length - 1
            ];
            assembly {
                mstore(numbersAvailable, sub(mload(numbersAvailable), 1))
            }
        }
        numbersDrawn = _sort(numbersDrawn);
        lottery.result = numbersDrawn;

        bytes32 jackPotHash = keccak256(abi.encode(numbersDrawn));
        uint256 numberOfJackpots = lottery.ticketCount[jackPotHash];

        emit NumbersDrawn(lotteryCounter, numbersDrawn, numberOfJackpots);

        if (numberOfJackpots != 0) {
            pauseLottery = true;
            lottery.jackPotPrize = currentJackPot;
            lottery.numberOfJackpots = numberOfJackpots;
            pendingWithdrawJackpotValue += currentJackPot;
            currentJackPot = 0;
        }

        if (pauseLottery) {
            currentStatus = LotteryStatus.NOT_STARTED;
        } else {
            currentStatus = LotteryStatus.ON_GOING;
            lotteryCounter++;
            lotteries[lotteryCounter].drawTime =
                lottery.drawTime +
                lotteryDuration;
        }
    }

    function _quickSort(
        uint8[6] memory arr,
        int left,
        int right
    ) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j) _quickSort(arr, left, j);
        if (i < right) _quickSort(arr, i, right);
    }

    function _sort(
        uint8[6] memory data
    ) internal pure returns (uint8[6] memory) {
        _quickSort(data, int(0), int(data.length - 1));
        return data;
    }

    function _checkLotteryNumbers(uint8[6] calldata numbers) internal pure {
        if (numbers[0] == 0 || numbers[5] > 47) {
            revert InvalidNumber();
        }

        for (uint256 i = 0; i < 5; i++) {
            if (numbers[i + 1] <= numbers[i]) {
                revert InvalidNumberOrder();
            }
        }
    }

    function _checkNumberOfMatches(
        uint8[6] memory ticket,
        uint8[6] memory lotteryNumbers
    ) internal pure returns (uint256 numberOfMatches) {
        bool[48] memory matches;
        for (uint256 i = 0; i < 6; i++) {
            matches[ticket[i]] = true;
        }
        for (uint256 j = 0; j < 6; j++) {
            if (matches[lotteryNumbers[j]]) {
                numberOfMatches++;
            }
        }
    }

    function _requestRandomNumbers() internal returns (uint256) {
        return
            IRandomizer(randomizerAddress).request(
                randomizerGasLimit,
                randomizerConfirmations
            );
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}

