// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./VRFConsumerBaseV2.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./ConfirmedOwner.sol";
import "./IGamesHub.sol";
import "./IERC20.sol";

contract CoinFlipGame is VRFConsumerBaseV2, ConfirmedOwner {
    event CoinFlipped(
        address indexed player,
        uint256 indexed nonce,
        uint256 indexed rngNonce,
        uint256 creditAmount
    );
    event GameFinished(
        uint256 indexed nonce,
        address indexed player,
        uint256 volumeIn,
        uint256 volumeOut,
        uint8 result,
        uint256 randomness,
        bool heads
    );
    event LimitsAndChancesChanged(
        uint256 maxLimit,
        uint256 minLimit,
        bool limitTypeFixed,
        uint8 feeFromBet,
        uint8 feePercFromWin
    );
    event GameRefunded(
        uint256 indexed nonce,
        address indexed player,
        uint256 volume
    );
    event ForcedResend(uint256 _nonce);

    IGamesHub public gamesHub;
    IERC20 public token;
    uint256 public totalBet;
    uint256 public maxLimit = 1000 * (10 ** 6); //default 1000 USDC
    uint256 public minLimit = 1 * (10 ** 6); //default 1 USDC
    uint256 public feeFromBet = 7 * (10 ** 4); //default 7 cents
    uint8 public feePercFromWin = 15;
    bool limitTypeFixed = true;
    uint256 totalGames = 0;

    struct Games {
        address player;
        uint256 amount;
        bool heads;
        uint8 result; // 0- not set, 1- win, 2- lose, 3- refunded
    }
    mapping(uint256 => Games) public games;

    VRFCoordinatorV2Interface COORDINATOR;

    // Chainlink subscription data struct, with the same subscription ID type as the VRF Coordinator
    uint64 s_subscriptionId;
    bytes32 keyHash;
    uint32 callbackGasLimit;
    uint16 requestConfirmations;

    mapping(uint256 => uint256) gameNonce;

    constructor(
        uint64 subscriptionId,
        address vrfCoordinator,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        address _gamesHub
    ) VRFConsumerBaseV2(vrfCoordinator) ConfirmedOwner(msg.sender) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        gamesHub = IGamesHub(_gamesHub);
        token = IERC20(gamesHub.helpers(keccak256("TOKEN")));
        totalBet = 0;
    }

    /**
     * @dev Flip the coin, setting the bet amount and the side of the coin
     * A request will be sent to the SupraOracles contract to get a random number
     * @param _heads Heads or Tails
     * @param _amount Amount of tokens to bet
     */
    function coinFlip(bool _heads, uint256 _amount) external {
        uint256 balance = token.balanceOf(address(this));

        if (limitTypeFixed) {
            require(_amount <= maxLimit && _amount >= minLimit, "CF-01");
        } else {
            require(
                _amount <= (maxLimit * balance) / 100 &&
                    _amount >= (minLimit * balance) / 100,
                "CF-01"
            );
        }

        require(balance >= ((totalBet + _amount) * 2), "CF-02");

        gamesHub.incrementNonce();
        
        _amount -= feeFromBet;

        token.transferFrom(msg.sender, address(this), _amount);
        // Sending fee to the house
        token.transferFrom(
            msg.sender,
            gamesHub.helpers(keccak256("TREASURY")),
            feeFromBet
        );

        games[gamesHub.nonce()] = Games(msg.sender, _amount, _heads, 0);

        uint256 nonce = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1
        );
        gameNonce[nonce] = gamesHub.nonce();

        totalBet += _amount;
        totalGames += 1;
        emit CoinFlipped(msg.sender, gamesHub.nonce(), nonce, _amount);
    }

    /**
     * @dev Callback function from the SupraOracles contract
     * @param _requestId Request ID of the random number
     * @param _randomWords Random number
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        Games storage game = games[gameNonce[_requestId]];
        if (game.result > 0) return;

        uint256 volume = 0;
        bool heads = (_randomWords[0] % 2) == 1;

        if ((heads && game.heads) || (!heads && !game.heads)) {
            game.result = 1;
            uint256 _fee = (game.amount * feePercFromWin) / 1000;
            volume = game.amount - _fee;
            token.transfer(game.player, volume);
            token.transfer(gamesHub.helpers(keccak256("TREASURY")), _fee);
        } else {
            game.result = 2;
        }
        totalBet -= game.amount;

        emit GameFinished(
            gameNonce[_requestId],
            game.player,
            game.amount,
            volume,
            game.result,
            _randomWords[0],
            heads
        );
    }

    /**
     * @dev Resend the game to the SupraOracles. To use only if some game is stuck.
     * @param _nonce Nonce of the game
     */
    function resendGame(uint256 _nonce) external {
        require(gamesHub.checkRole(gamesHub.ADMIN_ROLE(), msg.sender), "CF-05");

        uint256 nonce = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1
        );
        gameNonce[nonce] = gameNonce[_nonce];
        delete gameNonce[_nonce];

        emit ForcedResend(_nonce);
    }

    /**
     * @dev Refund the game to the player. To use only if some game is stuck.
     * @param _nonce Nonce of the game
     */
    function refundGame(uint256 _nonce) external {
        require(gamesHub.checkRole(gamesHub.ADMIN_ROLE(), msg.sender), "CF-05");
        Games storage game = games[_nonce];
        require(game.result == 0, "CF-04");

        token.transfer(game.player, game.amount);
        totalBet -= game.amount;
        game.result = 3;

        emit GameRefunded(_nonce, game.player, game.amount);
    }

    /**
     * @dev Change the house chance and bet limit
     * @param _maxLimit maximum bet limit
     * @param _minLimit minimum bet limit
     * @param _limitTypeFixed if true, the bet limit will be fixed, if false, the bet limit will be a percentage of the contract balance
     * @param _feeFromBet fee from the bet
     * @param _feePercFromWin fee percentage from the win
     */
    function changeLimitsAndChances(
        uint256 _maxLimit,
        uint256 _minLimit,
        bool _limitTypeFixed,
        uint8 _feeFromBet,
        uint8 _feePercFromWin
    ) public {
        require(gamesHub.checkRole(gamesHub.ADMIN_ROLE(), msg.sender), "CF-05");
        require(_maxLimit >= _minLimit, "CF-06");

        if (!limitTypeFixed) {
            require(_maxLimit <= 100 && _minLimit <= 100, "CF-12");
        }

        maxLimit = _maxLimit;
        minLimit = _minLimit;
        limitTypeFixed = _limitTypeFixed;
        feeFromBet = _feeFromBet;
        feePercFromWin = _feePercFromWin;

        emit LimitsAndChancesChanged(
            _minLimit,
            _maxLimit,
            _limitTypeFixed,
            _feeFromBet,
            _feePercFromWin
        );
    }

    /**
     * @dev Change the token address, sending the current token balance to the admin wallet
     * @param _token New token address
     */
    function changeToken(address _token) public {
        require(gamesHub.checkRole(gamesHub.ADMIN_ROLE(), msg.sender), "CF-05");
        require(totalBet == 0, "CF-07");

        token.transfer(gamesHub.adminWallet(), token.balanceOf(address(this)));
        token = IERC20(_token);
    }

    /**
     * @dev Change the key hash for the gwei price on chainlink
     * @param _keyHash New key hash
     */
    function changeKeyHash(bytes32 _keyHash) public {
        require(gamesHub.checkRole(gamesHub.ADMIN_ROLE(), msg.sender), "CF-05");
        keyHash = _keyHash;
    }

    /**
     * @dev Withdraw tokens from the contract to the admin wallet
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawTokens(uint256 _amount) public {
        require(gamesHub.checkRole(gamesHub.ADMIN_ROLE(), msg.sender), "CF-05");
        require(totalBet == 0, "CF-07");

        token.transfer(gamesHub.adminWallet(), _amount);
    }
}

