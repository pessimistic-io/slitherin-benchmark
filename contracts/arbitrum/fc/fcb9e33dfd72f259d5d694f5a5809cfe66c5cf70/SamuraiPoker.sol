// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Address.sol";

// import "hardhat/console.sol";

interface ILottoRNG {
    function requestRandomNumbers(
        uint256 n,
        uint256 gasLimit
    ) external payable returns (uint256 id);

    function getFee(uint256 gasLimit) external view returns (uint256 fee);

    function depositFee() external payable;
}

interface IEngine {
    function getWinner(
        uint8[] calldata playerOneHand,
        uint8[] calldata playerTwoHand
    ) external view returns (uint8 winner);
}

interface IBankRoll {
    function deposit(address erc20Address, uint256 amount) external payable;
}

contract SamuraiPoker is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    using Address for address payable;

    ILottoRNG public lottoRNG;
    IEngine public engine;
    IBankRoll public bankRoll;
    Counters.Counter public totalGames;
    address[] public currencyList;
    uint256[] public openedGames;
    uint256[] public finishedGames;

    uint256 public gasLimit = 1000000;
    uint256 public houseEdge = 500;

    mapping(address => Currency) public allowedCurrencies;
    mapping(uint256 => Game) public games;
    mapping(address => uint256[]) public playerGames;
    mapping(uint256 => uint256) public randomRequests;

    struct Game {
        address playerOne;
        address playerTwo;
        uint256 requestId;
        uint256[] randomNumbers;
        address currency;
        uint256 bet;
        uint256 dateCreated;
        uint256 datePlayAgainst;
        uint256 dateClosed;
        uint8 winner;
        uint8[] playerOneHand;
        uint8[] playerTwoHand;
    }

    struct Currency {
        uint256 minBet;
        uint256 maxBet;
        bool accepted;
    }

    /* ========== INITIALIZER ========== */
    constructor(address _lottoRNGAddress, address _bankRollAddress) {
        lottoRNG = ILottoRNG(_lottoRNGAddress);
        bankRoll = IBankRoll(_bankRollAddress);
    }

    /* ========== FUNCTIONS ========== */

    function createGame(
        address erc20Address,
        uint256 amount
    ) external payable nonReentrant whenNotPaused {
        require(
            allowedCurrencies[erc20Address].accepted,
            "Currency is not accepted"
        );
        require(
            amount >= allowedCurrencies[erc20Address].minBet &&
                amount <= allowedCurrencies[erc20Address].maxBet,
            "minBet or maxBet error"
        );
        uint256 fee = lottoRNG.getFee(gasLimit) / 2;

        if (erc20Address == address(0)) {
            require(msg.value >= amount + fee, "Wrong amount");
        } else {
            require(msg.value >= fee, "Wrong amount");
            _transferIn(erc20Address, amount, _msgSender());
        }

        totalGames.increment();
        uint256 gameId = totalGames.current();
        games[gameId].playerOne = _msgSender();
        games[gameId].currency = erc20Address;
        games[gameId].bet = amount;
        games[gameId].dateCreated = block.timestamp;
        openedGames.push(gameId);
        playerGames[_msgSender()].push(gameId);
        lottoRNG.depositFee{value: fee}();
        emit GameCreated(
            gameId,
            _msgSender(),
            erc20Address,
            amount,
            block.timestamp
        );
    }

    function playAgainst(
        uint256 gameId
    ) external payable nonReentrant whenNotPaused {
        require(
            games[gameId].datePlayAgainst == 0 && games[gameId].dateClosed == 0,
            "Game is already running or finished"
        );
        require(
            games[gameId].playerOne != _msgSender(),
            "You can't play against yourself"
        );

        uint256 fee = lottoRNG.getFee(gasLimit) / 2;

        if (games[gameId].currency == address(0)) {
            require(msg.value >= games[gameId].bet + fee, "Wrong amount");
        } else {
            require(msg.value >= fee, "Wrong amount");
            _transferIn(
                games[gameId].currency,
                games[gameId].bet,
                _msgSender()
            );
        }

        games[gameId].playerTwo = _msgSender();
        games[gameId].datePlayAgainst = block.timestamp;
        uint256 requestId = lottoRNG.requestRandomNumbers{value: fee}(
            10,
            gasLimit
        );
        games[gameId].requestId = requestId;
        randomRequests[requestId] = gameId;
        playerGames[_msgSender()].push(gameId);
        emit PlayedAgainst(
            gameId,
            requestId,
            _msgSender(),
            games[gameId].currency,
            games[gameId].bet,
            block.timestamp
        );
    }

    function closeGame(uint256 gameId) external nonReentrant {
        require(games[gameId].dateCreated > 0, "Game is not created yet");
        require(
            games[gameId].playerOne == _msgSender() || owner() == _msgSender(),
            "You didn't create this game"
        );
        require(
            games[gameId].datePlayAgainst == 0 && games[gameId].dateClosed == 0,
            "Too late to close this game"
        );
        games[gameId].dateClosed == block.timestamp;
        _removeFromOpenedGames(gameId);
        if (games[gameId].currency == address(0)) {
            payable(games[gameId].playerOne).sendValue(games[gameId].bet);
        } else {
            _transferOut(
                games[gameId].currency,
                games[gameId].bet,
                games[gameId].playerOne
            );
        }
        emit GameClosed(gameId, block.timestamp);
    }

    /* ========== RNG FUNCTION ========== */
    function receiveRandomNumbers(
        uint256 _id,
        uint256[] calldata values
    ) external {
        require(_msgSender() == address(lottoRNG), "LottoRNG Only");
        uint256 gameId = randomRequests[_id];
        require(games[gameId].dateClosed == 0, "Game already closed");

        games[gameId].randomNumbers = values;
        games[gameId].dateClosed = block.timestamp;
        (uint8[] memory playerOneHand, uint8[] memory playerTwoHand) = getCards(
            values
        );
        games[gameId].playerOneHand = playerOneHand;
        games[gameId].playerTwoHand = playerTwoHand;
        games[gameId].dateClosed = block.timestamp;

        uint8 winner = engine.getWinner(playerOneHand, playerTwoHand);
        games[gameId].winner = winner;
        _removeFromOpenedGames(gameId);
        (
            uint256 prizeWithoutHouseEdge,
            uint256 houseEdgeAmount
        ) = _getHouseEdgeAmount(games[gameId].bet * 2);
        if (winner == 0) {
            _transferOut(
                games[gameId].currency,
                prizeWithoutHouseEdge / 2,
                games[gameId].playerOne
            );
            _transferOut(
                games[gameId].currency,
                prizeWithoutHouseEdge / 2,
                games[gameId].playerTwo
            );
        } else if (winner == 1) {
            _transferOut(
                games[gameId].currency,
                prizeWithoutHouseEdge,
                games[gameId].playerOne
            );
        } else if (winner == 2) {
            _transferOut(
                games[gameId].currency,
                prizeWithoutHouseEdge,
                games[gameId].playerTwo
            );
        }
        if (games[gameId].currency == address(0)) {
            bankRoll.deposit{value: houseEdgeAmount}(
                address(0),
                houseEdgeAmount
            );
        } else {
            IERC20(games[gameId].currency).approve(
                address(bankRoll),
                houseEdgeAmount
            );
            bankRoll.deposit(games[gameId].currency, houseEdgeAmount);
        }
        emit RandomNumbersReceived(
            gameId,
            playerOneHand,
            playerTwoHand,
            winner,
            games[gameId].currency,
            games[gameId].bet,
            block.timestamp
        );
    }

    /* ========== ADMIN FUNCTIONS ========== */
    function setLottoRNG(address lottoRNGAddress) external onlyOwner {
        lottoRNG = ILottoRNG(lottoRNGAddress);
        emit LottoRNGSet(lottoRNGAddress);
    }

    function setEngine(address engineAddress) external onlyOwner {
        engine = IEngine(engineAddress);
        emit EngineSet(engineAddress);
    }

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
        emit GasLimitSet(_gasLimit);
    }

    function setHouseEdge(uint256 _houseEdge) external onlyOwner {
        houseEdge = _houseEdge;
        emit HouseEdgeSet(_houseEdge);
    }

    function addCurrency(
        address _currencyAddress,
        uint256 _minBet,
        uint256 _maxBet
    ) external onlyOwner {
        require(
            !allowedCurrencies[_currencyAddress].accepted,
            "Currency is already accepted"
        );
        currencyList.push(_currencyAddress);
        allowedCurrencies[_currencyAddress] = Currency({
            minBet: _minBet,
            maxBet: _maxBet,
            accepted: true
        });
    }

    function removeCurrency(address _currencyAddress) external onlyOwner {
        require(
            allowedCurrencies[_currencyAddress].accepted,
            "Currency is not accepted"
        );
        delete allowedCurrencies[_currencyAddress];
        for (uint i = 0; i < currencyList.length; i++) {
            if (currencyList[i] == _currencyAddress) {
                currencyList[i] = currencyList[currencyList.length - 1];
                currencyList.pop();
                break;
            }
        }
    }

    function setMinMaxBet(
        address _currencyAddress,
        uint256 _minBet,
        uint256 _maxBet
    ) external onlyOwner {
        require(
            allowedCurrencies[_currencyAddress].accepted,
            "Currency is not accepted"
        );
        allowedCurrencies[_currencyAddress].minBet = _minBet;
        allowedCurrencies[_currencyAddress].maxBet = _maxBet;
        emit MinMaxBetSet(_currencyAddress, _minBet, _maxBet);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function rescue(address erc20Address, uint256 amount) external onlyOwner {
        if (erc20Address == address(0)) {
            payable(_msgSender()).sendValue(amount);
        } else {
            IERC20(erc20Address).safeTransfer(_msgSender(), amount);
        }
    }

    function rescueAll(address erc20Address) external onlyOwner {
        if (erc20Address == address(0)) {
            payable(_msgSender()).sendValue(address(this).balance);
        } else {
            IERC20(erc20Address).safeTransfer(
                _msgSender(),
                IERC20(erc20Address).balanceOf(address(this))
            );
        }
    }

    /* ========== UTILS ========== */
    function _transferIn(
        address token,
        uint256 amount,
        address sender
    ) internal returns (uint256 transferedAmount) {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(sender, address(this), amount);
        transferedAmount =
            IERC20(token).balanceOf(address(this)) -
            balanceBefore;
    }

    function _transferOut(
        address token,
        uint256 amount,
        address recipient
    ) internal returns (uint256 transferedAmount) {
        if (token == address(0)) {
            uint256 balanceBefore = address(this).balance;
            payable(recipient).sendValue(amount);
            transferedAmount = balanceBefore - address(this).balance;
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(recipient, amount);
            transferedAmount =
                balanceBefore -
                IERC20(token).balanceOf(address(this));
        }
    }

    function _removeFromOpenedGames(uint256 _gameId) internal {
        for (uint256 i = 0; i < openedGames.length; i++) {
            if (openedGames[i] == _gameId) {
                openedGames[i] = openedGames[openedGames.length - 1];
                openedGames.pop();
                break;
            }
        }
        finishedGames.push(_gameId);
    }

    function getCards(
        uint256[] calldata randomValues
    )
        public
        pure
        returns (uint8[] memory playerOneHand, uint8[] memory playerTwoHand)
    {
        playerOneHand = new uint8[](5);
        playerTwoHand = new uint8[](5);
        for (uint8 i = 0; i < randomValues.length; i++) {
            if (i < 5) {
                playerOneHand[i] = uint8(randomValues[i] % 6);
            } else {
                playerTwoHand[i - 5] = uint8(randomValues[i] % 6);
            }
        }
    }

    function _getHouseEdgeAmount(
        uint256 amount
    )
        internal
        view
        returns (uint256 prizeWithoutHouseEdge, uint256 houseEdgeAmount)
    {
        houseEdgeAmount = (amount * houseEdge) / 10_000;
        prizeWithoutHouseEdge = amount - houseEdgeAmount;
    }

    /* ========== GETTERS ========== */
    function getOpenedGames()
        external
        view
        returns (uint256[] memory _openedGames)
    {
        _openedGames = openedGames;
    }

    function getLastFinishedGames(
        uint256 length
    ) external view returns (uint256[] memory lastFinishedGames) {
        lastFinishedGames = new uint[](length);
        for (uint i = 0; i < length; i++) {
            lastFinishedGames[i] = finishedGames[
                finishedGames.length - length + i
            ];
        }
    }

    function getPlayerGames(
        address playerAddress
    ) external view returns (uint256[] memory _playerGames) {
        _playerGames = playerGames[playerAddress];
    }

    function getRandomResults(
        uint256 gameId
    ) external view returns (uint256[] memory values) {
        values = games[gameId].randomNumbers;
    }

    function getPlayersHands(
        uint256 gameId
    )
        external
        view
        returns (uint8[] memory playerOneHand, uint8[] memory playerTwoHand)
    {
        playerOneHand = games[gameId].playerOneHand;
        playerTwoHand = games[gameId].playerTwoHand;
    }

    function getGameData(
        uint256 gameId
    ) external view returns (Game memory game) {
        game = Game({
            playerOne: games[gameId].playerOne,
            playerTwo: games[gameId].playerTwo,
            requestId: games[gameId].requestId,
            randomNumbers: games[gameId].randomNumbers,
            currency: games[gameId].currency,
            bet: games[gameId].bet,
            dateCreated: games[gameId].dateCreated,
            datePlayAgainst: games[gameId].datePlayAgainst,
            dateClosed: games[gameId].dateClosed,
            winner: games[gameId].winner,
            playerOneHand: games[gameId].playerOneHand,
            playerTwoHand: games[gameId].playerTwoHand
        });
    }

    /* ========== EVENTS ========== */
    event MinMaxBetSet(address indexed currency, uint256 min, uint256 max);
    event HouseEdgeSet(uint256 houseEdge);
    event GasLimitSet(uint256 gasLimit);
    event EngineSet(address engine);
    event LottoRNGSet(address rng);
    event RandomNumbersReceived(
        uint256 gameId,
        uint8[] playerOneHand,
        uint8[] playerTwoHand,
        uint8 winner,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
    event GameClosed(uint256 gameId, uint256 timestamp);
    event PlayedAgainst(
        uint256 gameId,
        uint256 requestId,
        address player,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
    event GameCreated(
        uint256 gameId,
        address player,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
}

