//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./RrpRequesterV0.sol";
import "./IUniswapV2Router02.sol";

contract HighOrLowBurner is Ownable, RrpRequesterV0 {
    enum Direction {
        Under,
        Over
    }

    struct Fees {
        uint16 treasury;
        uint16 burn;
        uint16 swap;
    }

    struct Token {
        bool isActive;
        Fees fee;
        address router;
        address[] path;
        uint256 maxBet;
        uint256 swapValue;
        uint256 currentBalance;
    }

    struct Game {
        Direction direction; //0-under, 1-over
        uint8 rolledNumber;
        uint32 timestamp;
        address betToken;
        address player;
        uint256 betAmount;
        uint256 wonAmount;
    }

    mapping(address => Token) public tokenInfo;
    mapping(address => mapping(uint256 => Game)) public games;
    mapping(uint256 => Game) public idToGame;
    mapping(address => uint256) public totalPlayed;
    mapping(bytes32 => uint256) internal requestToGame;

    uint8 public rollOver = 55;
    uint8 public rollUnder = 45;
    uint256 public gameId;

    address public treasury = 0x0Ba7D8d8A8B39c49215bc6EC45C8b0718593e466;
    address[] public activeTokens;

    /** Arbitrum Mainnet */
    address public airnode = 0x9d3C147cA16DB954873A498e0af5852AB39139f2;
    address public rrpAddress = 0xb015ACeEdD478fc497A798Ab45fcED8BdEd08924;
    bytes32 public endpointIdUint256 = 0xfb6d017bb87991b7495f563db3c8cf59ff87b09781947bb1e417006ad7f55a78;
    address public sponsorWallet;

    event DicePlayed(
        uint256 indexed gameId,
        address indexed player,
        address indexed token,
        uint256 amount,
        Direction direction,
        uint256 timestamp
    );
    event GameResult(
        uint256 indexed gameId,
        address indexed player,
        Direction direction,
        uint256 result,
        uint256 amount
    );

    constructor() RrpRequesterV0(rrpAddress) {
        address _token = 0x1C7F32699Ff9163f928089C0a4D6EE5Ad5885C6f; //GSHIBA
        address _router = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506; //SUSHI ROUTER

        address[] memory _path = new address[](2);
        _path[0] = _token;
        _path[1] = IUniswapV2Router02(_router).WETH();

        tokenInfo[_token] = Token({
            isActive: true,
            fee: Fees({ treasury: 90, burn: 300, swap: 10 }),
            router: _router,
            path: _path,
            maxBet: 20000000 * 10 ** 18,
            swapValue: 100000000 * 10 ** 18,
            currentBalance: 0
        });

        IERC20(_token).approve(_router, type(uint256).max);
        activeTokens.push(_token);
    }

    function setToken(
        address _token,
        bool _isActive,
        uint256 _swapValue,
        address _router,
        address[] memory _path,
        uint256 _maxBet,
        Fees memory _fee
    ) external onlyOwner {
        Token storage tkn = tokenInfo[_token];

        if (_isActive) {
            if (!tkn.isActive) {
                IERC20(_token).approve(_router, type(uint256).max);
                activeTokens.push(_token);
            }
        } else {
            for (uint256 i = 0; i < activeTokens.length; i++) {
                if (activeTokens[i] == _token) {
                    activeTokens[i] = activeTokens[activeTokens.length - 1];
                    activeTokens.pop();
                }
            }
        }

        tkn.isActive = _isActive;
        tkn.swapValue = _swapValue;
        tkn.maxBet = _maxBet;
        tkn.fee = _fee;
        tkn.router = _router;
        tkn.path = _path;
    }

    function setDiceInfo(uint8 _newOver, uint8 _newUnder) external onlyOwner {
        rollOver = _newOver;
        rollUnder = _newUnder;
    }

    function setSponsorWallet(address _newWallet) external onlyOwner {
        sponsorWallet = _newWallet;
    }

    function playDice(Direction _overOrUnder, address _token, uint256 _betAmount) external payable {
        Token memory tkn = tokenInfo[_token];
        Game storage game = idToGame[gameId];
        IERC20(_token).transferFrom(msg.sender, address(this), _betAmount);

        require(tkn.isActive, "Invalid playing token");
        require(_betAmount <= tkn.maxBet, "Amount exceeds limit");
        require(
            IERC20(_token).balanceOf(address(this)) - tkn.currentBalance >= _betAmount * 2,
            "Not enough funds to payout win"
        );

        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );

        requestToGame[requestId] = gameId;

        game.player = msg.sender;
        game.betAmount = _betAmount;
        game.direction = _overOrUnder;
        game.betToken = _token;
        game.timestamp = uint32(block.timestamp);

        emit DicePlayed(gameId, msg.sender, _token, _betAmount, _overOrUnder, block.timestamp);

        gameId++;
    }

    function fulfillUint256(bytes32 requestId, bytes calldata data) external onlyAirnodeRrp {
        uint256 _gameId = requestToGame[requestId];
        Game storage game = idToGame[_gameId];
        Token storage tkn = tokenInfo[game.betToken];

        uint256 qrngUint256 = abi.decode(data, (uint256));
        uint256 randomNum = qrngUint256 % 101;
        game.rolledNumber = uint8(randomNum);
        games[game.player][totalPlayed[game.player]] = Game(
            game.direction,
            game.rolledNumber,
            game.timestamp,
            game.betToken,
            game.player,
            game.betAmount,
            game.wonAmount
        );
        totalPlayed[game.player]++;

        if (
            (game.direction == Direction.Under && randomNum <= rollUnder) ||
            (game.direction == Direction.Over && randomNum >= rollOver)
        ) {
            game.wonAmount = game.betAmount * 2;
            games[game.player][totalPlayed[game.player]].wonAmount = game.wonAmount;
            IERC20(game.betToken).transfer(game.player, game.wonAmount);
        } else {
            IERC20 token = IERC20(game.betToken);
            uint256 amount = game.betAmount;

            uint256 treasuryFee = (amount * tkn.fee.treasury) / 1000;
            uint256 burnFee = (amount * tkn.fee.burn) / 1000;
            uint256 swapFee = (amount * tkn.fee.swap) / 1000;

            token.transfer(treasury, treasuryFee);
            token.transfer(address(0xdead), burnFee);
            tkn.currentBalance += swapFee;

            if (tkn.currentBalance >= tkn.swapValue) {
                IUniswapV2Router02 router = IUniswapV2Router02(tkn.router);
                router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    tkn.currentBalance,
                    0,
                    tkn.path,
                    treasury,
                    block.timestamp + 60
                );
                tkn.currentBalance = 0;
            }
        }

        emit GameResult(_gameId, game.player, game.direction, game.rolledNumber, game.wonAmount);
    }

    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0x0)) {
            payable(owner()).transfer(_amount);
            return;
        }
        IERC20 token = IERC20(_token);
        token.transfer(owner(), _amount);
    }

    function getActiveTokens() external view returns (address[] memory) {
        return activeTokens;
    }
}

