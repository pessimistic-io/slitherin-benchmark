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
    function getWinners(
        uint8[5][] calldata playerHands
    ) external view returns (uint8[] memory winners);
}

interface IBankRoll {
    function deposit(
        address erc20Address,
        uint256 amount,
        bytes32 ref
    ) external payable;
}

contract SamuraiPokerV3 is Ownable, Pausable, ReentrancyGuard {
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

    uint256 public gasLimitPerPlayer = 600_000;

    mapping(address => Currency) public allowedCurrencies;
    mapping(uint256 => Game) public games;
    mapping(uint256 => uint256) public randomRequests;
    mapping(address => PlayerStats) playerStats;
    mapping(address => CurrencyStats) public currencyStats;

    struct Game {
        Player[4] players;
        uint8 playersQuantity;
        uint256 requestId;
        uint256[] randomNumbers;
        address currency;
        uint256 bet;
        uint256 dateCreated;
        uint256 dateLaunched;
        uint256 dateClosed;
        uint8[] winners;
    }

    struct Player {
        address wallet;
        uint256 dateJoined;
        uint8[5] hand;
        bytes32 ref;
    }

    struct PlayerStats {
        uint256[3][3] WLD; // 2p/3p/4p -- wins/losses/draws
        uint256[] gamesPlayed;
    }

    struct CurrencyStats {
        uint256 gamesPlayed;
        uint256 amount;
    }

    struct Currency {
        uint256 minBet;
        uint256 maxBet;
        bool accepted;
        uint256 houseEdge;
    }

    /* ========== INITIALIZER ========== */
    constructor(address _lottoRNGAddress, address _bankRollAddress) {
        lottoRNG = ILottoRNG(_lottoRNGAddress);
        bankRoll = IBankRoll(_bankRollAddress);
    }

    /* ========== FUNCTIONS ========== */

    function createGame(
        address erc20Address,
        uint256 amount,
        uint8 playersQuantity,
        bytes32 ref
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
        require(
            playersQuantity >= 2 && playersQuantity <= 4,
            "Wrong amount of players"
        );

        uint256 fee = lottoRNG.getFee(gasLimitPerPlayer * playersQuantity) /
            playersQuantity;
        if (erc20Address == address(0)) {
            require(msg.value >= amount + fee, "Wrong amount");
        } else {
            require(msg.value >= fee, "Wrong amount");
            _transferIn(erc20Address, amount, _msgSender());
        }

        totalGames.increment();
        uint256 gameId = totalGames.current();
        games[gameId].playersQuantity = playersQuantity;
        games[gameId].currency = erc20Address;
        games[gameId].bet = amount;
        games[gameId].dateCreated = block.timestamp;
        _joinGame(gameId, 0, _msgSender(), ref);
        openedGames.push(gameId);
        lottoRNG.depositFee{value: fee}();
        emit GameCreated(
            gameId,
            _msgSender(),
            games[gameId].players,
            games[gameId].playersQuantity,
            erc20Address,
            amount,
            block.timestamp
        );
    }

    function joinGame(
        uint256 gameId,
        uint8 slot,
        bytes32 ref
    ) external payable nonReentrant whenNotPaused {
        require(
            slot >= 0 && slot < games[gameId].playersQuantity,
            "Wrong slot"
        );
        require(
            games[gameId].players[slot].wallet == address(0),
            "Slot is not available"
        );
        require(
            games[gameId].dateLaunched == 0 && games[gameId].dateClosed == 0,
            "Game is already running or finished"
        );
        uint256 fee = lottoRNG.getFee(
            gasLimitPerPlayer * games[gameId].playersQuantity
        ) / games[gameId].playersQuantity;
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
        _joinGame(gameId, slot, _msgSender(), ref);
        lottoRNG.depositFee{value: fee}();
        emit PlayerJoined(
            gameId,
            _msgSender(),
            slot,
            games[gameId].players,
            games[gameId].currency,
            games[gameId].bet,
            block.timestamp
        );
        if (_isGameFull(gameId)) {
            _launchGame(gameId);
            emit GameLaunched(
                gameId,
                games[gameId].requestId,
                games[gameId].players,
                games[gameId].currency,
                games[gameId].bet,
                block.timestamp
            );
        }
    }

    function leaveGame(uint256 gameId, uint8 slot) external nonReentrant {
        require(
            _msgSender() == games[gameId].players[slot].wallet,
            "You can't leave this slot"
        );
        require(
            games[gameId].dateLaunched == 0 && games[gameId].dateClosed == 0,
            "Game is already running or finished"
        );
        _leaveGame(gameId, slot, _msgSender());
        emit PlayerLeft(
            gameId,
            _msgSender(),
            games[gameId].players,
            block.timestamp
        );
        if (_isGameEmpty(gameId)) {
            _closeGame(gameId);
            emit GameClosed(gameId, block.timestamp);
        }
    }

    function closeGame(uint256 gameId) external nonReentrant onlyOwner {
        require(games[gameId].dateCreated > 0, "Game is not created yet");
        require(
            games[gameId].dateLaunched == 0 && games[gameId].dateClosed == 0,
            "Too late to close this game"
        );

        for (uint8 i = 0; i < games[gameId].playersQuantity; i++) {
            if (games[gameId].players[i].wallet != address(0)) {
                _leaveGame(gameId, i, games[gameId].players[i].wallet);
            }
        }
        _closeGame(gameId);
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
        uint8[5][] memory playerCards = getCards(values);
        for (uint8 i = 0; i < games[gameId].playersQuantity; i++) {
            games[gameId].players[i].hand = playerCards[i];
        }
        games[gameId].dateClosed = block.timestamp;
        games[gameId].winners = engine.getWinners(playerCards);
        _removeFromOpenedGames(gameId);

        if (games[gameId].winners[0] == 0) {
            for (uint8 i = 0; i < games[gameId].playersQuantity; i++) {
                _transferOut(
                    games[gameId].currency,
                    games[gameId].bet,
                    games[gameId].players[i].wallet
                );
            }
        } else {
            (
                uint256 prizeWithoutHouseEdge,
                uint256 houseEdgeAmount
            ) = _getHouseEdgeAmount(
                    games[gameId].currency,
                    games[gameId].bet * games[gameId].playersQuantity
                );

            for (uint8 i = 0; i < games[gameId].winners.length; i++) {
                _transferOut(
                    games[gameId].currency,
                    prizeWithoutHouseEdge / games[gameId].winners.length,
                    games[gameId].players[games[gameId].winners[i] - 1].wallet
                );
            }
            _depositToBankRoll(gameId, houseEdgeAmount);
        }
        _updatePlayersStats(gameId);
        _updateCurrencyStats(
            games[gameId].currency,
            games[gameId].bet * games[gameId].playersQuantity
        );
        emit RandomNumbersReceived(
            gameId,
            games[gameId].players,
            games[gameId].winners,
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

    function setBankRoll(address bankRollAddress) external onlyOwner {
        bankRoll = IBankRoll(bankRollAddress);
        emit BankRollSet(bankRollAddress);
    }

    function setGasLimitPerPlayer(
        uint256 _gasLimitPerPlayer
    ) external onlyOwner {
        gasLimitPerPlayer = _gasLimitPerPlayer;
        emit GasLimitSetPerPlayer(_gasLimitPerPlayer);
    }

    function addCurrency(
        address _currencyAddress,
        uint256 _minBet,
        uint256 _maxBet,
        uint256 _houseEdge
    ) external onlyOwner {
        require(
            !allowedCurrencies[_currencyAddress].accepted,
            "Currency is already accepted"
        );
        currencyList.push(_currencyAddress);
        allowedCurrencies[_currencyAddress] = Currency({
            minBet: _minBet,
            maxBet: _maxBet,
            accepted: true,
            houseEdge: _houseEdge
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

    function setCurrencyStats(
        address _currencyAddress,
        uint256 _games,
        uint256 _amount
    ) external onlyOwner {
        currencyStats[_currencyAddress].gamesPlayed = _games;
        currencyStats[_currencyAddress].amount = _amount;
    }

    function setTotalGames(uint256 _amount) external onlyOwner {
        totalGames._value = _amount;
    }

    function setPlayerStats(
        uint256[3] calldata twoplayers,
        uint256[3] calldata threeplayers,
        uint256[3] calldata fourplayers,
        address playerAddress
    ) external onlyOwner {
        playerStats[playerAddress].WLD[0] = twoplayers;
        playerStats[playerAddress].WLD[1] = threeplayers;
        playerStats[playerAddress].WLD[2] = fourplayers;
    }

    function setHouseEdge(
        address _currencyAddress,
        uint256 _houseEdge
    ) external onlyOwner {
        require(
            allowedCurrencies[_currencyAddress].accepted,
            "Currency is not accepted"
        );
        allowedCurrencies[_currencyAddress].houseEdge = _houseEdge;
        emit HouseEdgeSet(_currencyAddress, _houseEdge);
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

    function _depositToBankRoll(
        uint256 gameId,
        uint256 amount
    ) internal returns (uint256 depositedAmount) {
        address token = games[gameId].currency;
        uint8 playersQuantity = games[gameId].playersQuantity;
        if (token == address(0)) {
            uint256 balanceBefore = address(this).balance;
            for (uint8 i = 0; i < playersQuantity; i++) {
                bankRoll.deposit{value: amount / playersQuantity}(
                    address(0),
                    amount / playersQuantity,
                    games[gameId].players[i].ref
                );
            }

            depositedAmount = balanceBefore - address(this).balance;
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).approve(address(bankRoll), amount);
            for (uint8 i = 0; i < playersQuantity; i++) {
                bankRoll.deposit(
                    token,
                    amount / playersQuantity,
                    games[gameId].players[i].ref
                );
            }
            depositedAmount =
                balanceBefore -
                IERC20(token).balanceOf(address(this));
        }
    }

    function _updatePlayersStats(uint256 gameId) internal {
        if (games[gameId].winners[0] == 0) {
            for (uint8 i = 0; i < games[gameId].playersQuantity; i++) {
                playerStats[games[gameId].players[i].wallet].WLD[
                    games[gameId].playersQuantity - 2
                ][2] += 1;
            }
        } else {
            for (uint8 i = 0; i < games[gameId].playersQuantity; i++) {
                bool playerWon = false;
                for (uint8 j = 0; j < games[gameId].winners.length; j++) {
                    if (games[gameId].winners[j] == i + 1) {
                        playerWon = true;
                    }
                }
                if (playerWon) {
                    playerStats[games[gameId].players[i].wallet].WLD[
                        games[gameId].playersQuantity - 2
                    ][0] += 1;
                } else {
                    playerStats[games[gameId].players[i].wallet].WLD[
                        games[gameId].playersQuantity - 2
                    ][1] += 1;
                }
            }
        }
    }

    function _updateCurrencyStats(address currency, uint256 amount) internal {
        currencyStats[currency].gamesPlayed += 1;
        currencyStats[currency].amount += amount;
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

    function _removeFromPlayerGames(
        uint256 _gameId,
        address _playerAddress
    ) internal {
        for (
            uint256 i = 0;
            i < playerStats[_playerAddress].gamesPlayed.length;
            i++
        ) {
            if (playerStats[_playerAddress].gamesPlayed[i] == _gameId) {
                playerStats[_playerAddress].gamesPlayed[i] = playerStats[
                    _playerAddress
                ].gamesPlayed[
                        playerStats[_playerAddress].gamesPlayed.length - 1
                    ];
                playerStats[_playerAddress].gamesPlayed.pop();
                break;
            }
        }
    }

    function getCards(
        uint256[] calldata randomValues
    ) public pure returns (uint8[5][] memory playersHands) {
        playersHands = new uint8[5][](randomValues.length / 5);
        for (uint8 i = 0; i < randomValues.length; i++) {
            playersHands[i / 5][i % 5] = uint8(randomValues[i] % 6);
        }
    }

    function _getHouseEdgeAmount(
        address currencyAddress,
        uint256 amount
    )
        internal
        view
        returns (uint256 prizeWithoutHouseEdge, uint256 houseEdgeAmount)
    {
        houseEdgeAmount =
            (amount * allowedCurrencies[currencyAddress].houseEdge) /
            10_000;
        prizeWithoutHouseEdge = amount - houseEdgeAmount;
    }

    function _joinGame(
        uint256 gameId,
        uint8 slot,
        address playerAddress,
        bytes32 ref
    ) internal {
        if (!_isAlreadyIn(gameId, playerAddress)) {
            playerStats[playerAddress].gamesPlayed.push(gameId);
        }
        games[gameId].players[slot].wallet = playerAddress;
        games[gameId].players[slot].dateJoined = block.timestamp;
        games[gameId].players[slot].ref = ref;
    }

    function _leaveGame(
        uint256 gameId,
        uint8 slot,
        address playerAddress
    ) internal {
        delete games[gameId].players[slot].wallet;
        delete games[gameId].players[slot].dateJoined;
        delete games[gameId].players[slot].ref;
        _removeFromPlayerGames(gameId, playerAddress);
        _transferOut(games[gameId].currency, games[gameId].bet, playerAddress);
    }

    function _isGameFull(uint256 gameId) internal view returns (bool isFull) {
        isFull = true;
        for (uint256 i = 0; i < games[gameId].playersQuantity; i++) {
            if (games[gameId].players[i].wallet == address(0)) {
                isFull = false;
            }
        }
    }

    function _isGameEmpty(uint256 gameId) internal view returns (bool isEmpty) {
        isEmpty = true;
        for (uint256 i = 0; i < games[gameId].playersQuantity; i++) {
            if (games[gameId].players[i].wallet != address(0)) {
                isEmpty = false;
            }
        }
    }

    function _launchGame(uint256 gameId) internal {
        uint256 requestId = lottoRNG.requestRandomNumbers(
            5 * games[gameId].playersQuantity,
            gasLimitPerPlayer * games[gameId].playersQuantity
        );
        games[gameId].requestId = requestId;
        games[gameId].dateLaunched = block.timestamp;
        randomRequests[requestId] = gameId;
    }

    function _closeGame(uint256 gameId) internal {
        games[gameId].dateClosed = block.timestamp;
        _removeFromOpenedGames(gameId);
    }

    function _isAlreadyIn(
        uint256 gameId,
        address player
    ) internal view returns (bool isAlreadyIn) {
        for (uint8 i = 0; i < games[gameId].playersQuantity; i++) {
            if (games[gameId].players[i].wallet == player) {
                isAlreadyIn = true;
            }
        }
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
        if (length > finishedGames.length) {
            length = finishedGames.length;
        }
        lastFinishedGames = new uint[](length);
        for (uint i = 0; i < length; i++) {
            lastFinishedGames[i] = finishedGames[
                finishedGames.length - length + i
            ];
        }
    }

    function getPlayerStats(
        address playerAddress
    ) external view returns (PlayerStats memory _playerStats) {
        _playerStats = playerStats[playerAddress];
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
        returns (
            uint8[5] memory playerOneHand,
            uint8[5] memory playerTwoHand,
            uint8[5] memory playerThreeHand,
            uint8[5] memory playerFourHand
        )
    {
        playerOneHand = games[gameId].players[0].hand;
        playerTwoHand = games[gameId].players[1].hand;
        playerThreeHand = games[gameId].players[2].hand;
        playerFourHand = games[gameId].players[3].hand;
    }

    function getGameData(
        uint256 gameId
    ) external view returns (Game memory game) {
        game = games[gameId];
    }

    /* ========== EVENTS ========== */
    event MinMaxBetSet(address currency, uint256 min, uint256 max);
    event HouseEdgeSet(address currency, uint256 houseEdge);
    event GasLimitSetPerPlayer(uint256 gasLimitPerPlayer);
    event EngineSet(address engine);
    event BankRollSet(address bankRoll);
    event LottoRNGSet(address rng);
    event RandomNumbersReceived(
        uint256 gameId,
        Player[4] players,
        uint8[] winners,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
    event GameClosed(uint256 gameId, uint256 timestamp);
    event GameLaunched(
        uint256 gameId,
        uint256 requestId,
        Player[4] players,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
    event PlayerLeft(
        uint256 gameId,
        address player,
        Player[4] players,
        uint256 timestamp
    );
    event PlayerJoined(
        uint256 gameId,
        address player,
        uint8 slot,
        Player[4] players,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
    event GameCreated(
        uint256 gameId,
        address player,
        Player[4] players,
        uint8 playersQuantity,
        address currency,
        uint256 bet,
        uint256 timestamp
    );
}

