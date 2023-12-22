//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./IVault.sol";
import "./Types.sol";
import "./CoreUpgradeable.sol";

contract VaultManagerUpgradeable is
    ReentrancyGuardUpgradeable,
    CoreUpgradeable,
    IVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*==================================================== Events ====================================================*/

    event AmountIsTooBigForToReserved();
    event DirectPoolDeposit(
        address _tokenAddress,
        address _user,
        address _address,
        uint256 _amount
    );
    event TokensUpdated(address _token, bool _value);
    event FeeCollectorDeposit(
        address _address,
        address _token,
        uint256 _amount
    );
    event FeeCollectorPayout(address _address, address _token, uint256 _amount);
    event Refunded(address game, address player, address token, uint256 amount);

    /*==================================================== State Variables ====================================================*/

    mapping(address => bool) public whitelistedTokens;

    mapping(address => mapping(address => uint256)) public feeCollector;
    mapping(address => mapping(uint256 => Types.FeePerGame)) public feePerGame;
    mapping(address => uint256) public extraEdgeFee;
    mapping(address => Types.GameVault) public gamesVault;

    address public azuroLiquidityAddress;
    address public paraliqAddress;

    // Edges
    uint256 public constant FRONTEND_EDGE = 6000;
    uint256 public constant LIQUIDITY_EDGE = 1000;
    uint256 public constant GAME_PROVIDER_EDGE = 1500;
    // Paraliq and partner edges, limit to 1000
    uint256 public constant PARALIQ_EDGE = 700;
    uint256 public constant AZURO_LIQUIDITY_EDGE = 300;

    uint256 public constant MAX_WAGER_PERCENT = 200;
    uint256 public constant PERCENT_VALUE = 10000;

    /*==================================================== Modifiers ====================================================*/

    modifier onlyWhitelistedToken(address _token) {
        require(whitelistedTokens[_token], "VM: unknown token");
        _;
    }

    modifier onlyGame() {
        require(gamesVault[_msgSender()].isPresent, "VM: Not game");
        _;
    }

    modifier checkGameExistance(address _address) {
        require(gamesVault[_address].isPresent, "VM: Game does not exist");
        _;
    }

    modifier checkGamePerId(uint256 _gameId, bool _isPreent) {
        require(
            feePerGame[_msgSender()][_gameId].isPresent == _isPreent &&
                !feePerGame[_msgSender()][_gameId].isDone,
            "VM: Game id is already done"
        );
        _;
    }

    modifier setGamePerIdDone(uint256 _gameId) {
        require(
            feePerGame[_msgSender()][_gameId].isPresent,
            "VM: Game id does not exist"
        );
        require(
            feePerGame[_msgSender()][_gameId].isPresent &&
                !feePerGame[_msgSender()][_gameId].isDone,
            "VM: Game id is already done"
        );
        feePerGame[_msgSender()][_gameId].isDone = true;
        _;
    }

    modifier isGameCountAcceptable(uint256 _gameCount) {
        require(0 < _gameCount && _gameCount <= 100, "Game count out-range");
        _;
    }

    /*==================================================== Functions ====================================================*/

    /** @dev Creates a contract
     * @param _paraliqAddress paraliq savings address.
     * @param _azuroLiquidityAddress azuro savings address.
     */
    function initialize(
        address _paraliqAddress,
        address _azuroLiquidityAddress
    ) public payable initializer {
        __Core_init();
        __ReentrancyGuard_init();
        azuroLiquidityAddress = _azuroLiquidityAddress;
        paraliqAddress = _paraliqAddress;
        isWithdrawAvaialable = false;
        isWithdrawERC20Avaialable = false;
    }

    /** @dev adding amount to pool. Only reserved account.
     * @param _token one of the whitelisted tokens which is collected in settings
     * @param _sender holder of tokens
     * @param _sentAmount initial amount of token
     * @param _autoRollAmount number of games
     * @param _gameId  game id to identify fee
     * @param _toReserve reserving amount
     */
    function depositReservedAmount(
        address _token,
        address _sender,
        uint256 _sentAmount,
        uint256 _autoRollAmount,
        uint256 _gameId,
        uint256 _toReserve
    )
        external
        override
        onlyGame
        onlyWhitelistedToken(_token)
        isGameCountAcceptable(_autoRollAmount)
        checkGamePerId(_gameId, true)
    {
        _transferIn(_token, _sender, _sentAmount);
        uint256 wager_ = (_sentAmount *
            (PERCENT_VALUE - feePerGame[_msgSender()][_gameId].fee)) /
            PERCENT_VALUE;

        require(
            wager_ / _autoRollAmount >=
                gamesVault[_msgSender()].reservedAmount[_token].minWager,
            "VM: Wager is less minimum"
        );
        require(
            _toReserve / _autoRollAmount <= _getMaxPayout(_msgSender(), _token),
            "VM: Payout per game is higher than max possible"
        );
        require(
            _toReserve <= _getReserveLimit(_msgSender(), _token) + wager_,
            "VM: not enough funds on contract"
        );
        gamesVault[_msgSender()].reservedAmount[_token].amount += wager_;
        gamesVault[_msgSender()].reservedAmount[_token].reserved += _toReserve;
    }

    /** @dev withdraw amount from pool. Only reserved account.
     * @param _token one of available on the balance tokens
     * @param _amount amount to withdraw
     * @param _toReserve reserving amount to delete
     * @param _recipient where to withdraw
     */
    function withdrawReservedAmount(
        address _token,
        uint256 _amount,
        uint256 _toReserve,
        address _recipient
    ) external override onlyGame {
        if (_amount > 0) {
            gamesVault[_msgSender()].reservedAmount[_token].amount -= _amount;
            _transferOut(_token, _recipient, _amount);
            emit PayoutERC20(_token, _recipient, _amount, true);
        }
        gamesVault[_msgSender()].reservedAmount[_token].reserved -= _toReserve;
    }

    /** @dev predict fee percent per game and save it
     * @param _gameId game id to identify fee later
     */
    function predictFees(
        uint256 _gameId
    )
        external
        override
        onlyGame
        checkGamePerId(_gameId, false)
        returns (uint256 gameFee_)
    {
        gameFee_ = _calculateGameFee(_msgSender());
        feePerGame[_msgSender()][_gameId] = Types.FeePerGame({
            fee: gameFee_,
            isDone: false,
            isPresent: true
        });
    }

    /** @dev add fees to success tx.
     * @param _token one of available on the balance tokens
     * @param _frontendReferral frontend referral address
     * @param _gameProvider provider of the game
     * @param _sentValue initial amount
     * @param _gameId game id to identify fee later
     */
    function addFees(
        address _token,
        address _frontendReferral,
        address _gameProvider,
        uint256 _sentValue,
        uint256 _gameId
    ) external override onlyGame setGamePerIdDone(_gameId) {
        _addFees(
            _token,
            _msgSender(),
            _gameId,
            _sentValue,
            _frontendReferral,
            _gameProvider
        );
    }

    /** @dev refund funds if game unsuccess.
     * @param _token one of available on the balance tokens
     * @param _amount initial amount
     * @param _toReserve reserved amount
     * @param _player receipent to withdraw
     * @param _gameId game id to identify fee later
     */
    function refund(
        address _token,
        uint256 _amount,
        uint256 _toReserve,
        address _player,
        uint256 _gameId
    ) external override onlyGame setGamePerIdDone(_gameId) {
        uint256 wager_ = (_amount *
            (10000 - feePerGame[_msgSender()][_gameId].fee)) / PERCENT_VALUE;

        gamesVault[_msgSender()].reservedAmount[_token].amount -= wager_;
        gamesVault[_msgSender()].reservedAmount[_token].reserved -= _toReserve;
        _transferOut(_token, _player, _amount);

        emit Refunded(_msgSender(), _player, _token, _amount);

        delete feePerGame[_msgSender()][_gameId];
    }

    /** @dev adding value for reservedAmount object
     * @param _game game contract address
     * @param _token one of whitelisted token address
     * @param _amount amount to deposit
     */
    function directPoolDeposit(
        address _game,
        address _token,
        uint256 _amount
    )
        external
        override
        onlyGovernance
        onlyWhitelistedToken(_token)
        checkGameExistance(_game)
    {
        _transferIn(_token, _msgSender(), _amount);
        gamesVault[_game].reservedAmount[_token].amount += _amount;
        emit DirectPoolDeposit(_token, _msgSender(), _game, _amount);
    }

    /** @dev withdraw amount from feeCollector.
     * @param _token one of available on the balance tokens
     * @param _amount amount to withdraw
     */
    function withdrawFeeCollector(
        address _token,
        uint256 _amount
    ) external override nonReentrant {
        require(_amount > 0 && _amount <= feeCollector[_msgSender()][_token]);
        feeCollector[_msgSender()][_token] -= _amount;
        _transferOut(_token, _msgSender(), _amount);
    }

    /** @dev edits token whitelist
     * @param _token token address
     * @param _value whether true or false
     */
    function editWhitelistedTokens(
        address _token,
        bool _value
    ) external override onlyGovernance {
        whitelistedTokens[_token] = _value;

        emit TokensUpdated(_token, _value);
    }

    /** @dev Creates a contract
     * @param _paraliqAddress paraliq savings address.
     * @param _azuroLiquidityAddress azuro savings address.
     */
    function editAddresses(
        address _paraliqAddress,
        address _azuroLiquidityAddress
    ) external override onlyGovernance {
        azuroLiquidityAddress = _azuroLiquidityAddress;
        paraliqAddress = _paraliqAddress;
    }

    /** @dev withdraw from reservedAmount object
     * @param _game *
     * @param _token *
     * @param _amount *
     */
    function withdrawReservedAmountGovernance(
        address _game,
        address _token,
        uint256 _amount
    ) external override onlyGovernance checkGameExistance(_game) {
        require(
            gamesVault[_game].reservedAmount[_token].amount >=
                gamesVault[_game].reservedAmount[_token].reserved + _amount,
            "VM: Not enough funds on contract"
        );
        gamesVault[_game].reservedAmount[_token].amount -= _amount;
        _transferOut(_token, _msgSender(), _amount);
        emit PayoutERC20(_token, msg.sender, _amount, true);
    }

    /** @dev update minWager for token inside game
     * @param _game *
     * @param _token one of the whitelisted tokens which is collected in settings
     * @param _minWager the min amount of wager
     */
    function setMinWager(
        address _game,
        address _token,
        uint256 _minWager
    )
        external
        override
        onlyGovernance
        onlyWhitelistedToken(_token)
        checkGameExistance(_game)
    {
        gamesVault[_game].reservedAmount[_token].minWager = _minWager;
    }

    /** @dev calculates and if needed updates currentTransactionFee
     * @param _game str.
     */
    function editGameVault(
        address _game,
        bool _isPresent,
        Types.GameFee memory _transactionFee
    ) external override onlyGovernance {
        gamesVault[_game].gameFee = Types.GameFee({
            currentFee: _transactionFee.currentFee,
            nextFee: _transactionFee.nextFee,
            startTime: _transactionFee.startTime
        });
        gamesVault[_game].isPresent = _isPresent;
    }

    /** @dev edits token whitelist
     * @param _user user address
     * @param _value percent amount, ngt paraliqFee
     */
    function editExtraEdgeFee(
        address _user,
        uint256 _value
    ) external override onlyGovernance {
        require(_value <= PARALIQ_EDGE, "VM: Too big value");
        extraEdgeFee[_user] = _value;
    }

    /** @dev calculates and if needed updates GameFee
     * @param _game str.
     */
    function calculateGameFee(address _game) public override returns (uint256) {
        return _calculateGameFee(_game);
    }

    /*==================================================== Internal Functions ===========================================================*/

    /** @dev calculates and if needed updates GameFee
     * @param _token one of whitelisted tokens
     * @param _game game address
     * @param _gameId game id to identify fee later
     * @param _sentValue the initial sent value
     * @param _frontendReferral frontend referral address
     * @param _gameProvider game provder address
     */
    function _addFees(
        address _token,
        address _game,
        uint256 _gameId,
        uint256 _sentValue,
        address _frontendReferral,
        address _gameProvider
    ) internal {
        uint256 gameFee_ = feePerGame[_game][_gameId].fee;
        uint256 fee_ = ((_sentValue * gameFee_) / PERCENT_VALUE);

        {
            // liquidity edge
            gamesVault[_game].reservedAmount[_token].amount +=
                (fee_ * LIQUIDITY_EDGE) /
                PERCENT_VALUE;
            // frontend fee
            uint256 frontendExtraEdgeComputed_ = extraEdgeFee[
                _frontendReferral
            ];
            uint256 frontendEdgeComputed_ = (fee_ *
                (FRONTEND_EDGE + frontendExtraEdgeComputed_)) / PERCENT_VALUE;
            feeCollector[_frontendReferral][_token] += frontendEdgeComputed_;
            emit FeeCollectorDeposit(
                _frontendReferral,
                _token,
                frontendEdgeComputed_
            );

            // paraliq fee
            uint256 paraliqEdgeComputed_ = (fee_ *
                (PARALIQ_EDGE - frontendExtraEdgeComputed_)) / PERCENT_VALUE;
            feeCollector[paraliqAddress][_token] += paraliqEdgeComputed_;
            emit FeeCollectorDeposit(
                paraliqAddress,
                _token,
                paraliqEdgeComputed_
            );
        }

        {
            // gameProvider fee
            uint256 gameProviderEdgeComputed_ = (fee_ * (GAME_PROVIDER_EDGE)) /
                PERCENT_VALUE;
            feeCollector[_gameProvider][_token] += gameProviderEdgeComputed_;
            emit FeeCollectorDeposit(
                _gameProvider,
                _token,
                gameProviderEdgeComputed_
            );
        }

        {
            // azuroLiquidity fee
            uint256 azuroLiquidityEdgeComputed_ = (fee_ *
                (AZURO_LIQUIDITY_EDGE)) / PERCENT_VALUE;
            feeCollector[azuroLiquidityAddress][
                _token
            ] += azuroLiquidityEdgeComputed_;
            emit FeeCollectorDeposit(
                azuroLiquidityAddress,
                _token,
                azuroLiquidityEdgeComputed_
            );
        }
    }

    /** @dev calculates and if needed updates GameFee
     * @param _game *
     */
    function _calculateGameFee(
        address _game
    ) internal checkGameExistance(_game) returns (uint256) {
        Types.GameFee memory gameFee_ = gamesVault[_game].gameFee;
        if (gameFee_.nextFee != uint256(0)) {
            if (
                block.timestamp >= gameFee_.startTime &&
                gameFee_.startTime != uint256(0)
            ) {
                gamesVault[_game].gameFee = Types.GameFee({
                    currentFee: gameFee_.nextFee,
                    startTime: uint256(0),
                    nextFee: uint256(0)
                });
            }
        }
        return gamesVault[_game].gameFee.currentFee;
    }

    /** @dev returns reserve limit by game and token addresses
     * @param _game address of game contract
     * @param _token address of onw of whitelisted tokens
     */
    function _getReserveLimit(
        address _game,
        address _token
    )
        internal
        view
        onlyWhitelistedToken(_token)
        returns (uint256 reserveLimit_)
    {
        reserveLimit_ = gamesVault[_game].reservedAmount[_token].amount;
        uint256 pending_ = gamesVault[_game].reservedAmount[_token].reserved;

        if (reserveLimit_ > pending_) {
            reserveLimit_ -= pending_;
        } else {
            reserveLimit_ = 0;
        }
    }

    /** @dev returns max possible payout by game and token addresses
     * @param _game address of game contract
     * @param _token address of one of whitelisted tokens
     */
    function _getMaxPayout(
        address _game,
        address _token
    ) internal view onlyWhitelistedToken(_token) returns (uint256 maxWager_) {
        maxWager_ =
            (gamesVault[_game].reservedAmount[_token].amount *
                MAX_WAGER_PERCENT) /
            PERCENT_VALUE;
        uint256 pending_ = gamesVault[_game].reservedAmount[_token].reserved;

        if (maxWager_ > pending_) {
            maxWager_ -= pending_;
        } else {
            maxWager_ = 0;
        }
    }

    /**  @dev transfers any whitelisted token into here
     * @param _token one of the whitelisted tokens which is collected in settings
     * @param _sender holder of tokens
     * @param _amount the amount of token
     */
    function _transferIn(
        address _token,
        address _sender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeTransferFrom(
            _sender,
            address(this),
            _amount
        );
    }

    /** @dev transfers any whitelisted token to recipient
     * @param _token one of the whitelisted tokens which is collected in settings
     * @param _recipient receiver of tokens
     * @param _amount the amount of token
     */
    function _transferOut(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeTransfer(_recipient, _amount);
    }

    /*==================================================== View Functions ===========================================================*/

    /** @dev returns whether token is whitelisted or not
     * @param _token address of the token contract
     */
    function getWhitelistedToken(
        address _token
    ) external view override returns (bool) {
        return whitelistedTokens[_token];
    }

    function getGameVault(
        address _game
    ) external view override returns (Types.GameVaultReturn memory) {
        Types.GameVault storage gameVault_ = gamesVault[_game];
        return
            Types.GameVaultReturn({
                gameFee: gameVault_.gameFee,
                isPresent: gameVault_.isPresent
            });
    }

    /** @dev returns reserve amount object by game and token addresses
     * @param _game address of game contract
     * @param _token address of onw of whitelisted tokens
     */
    function getReservedAmount(
        address _game,
        address _token
    )
        external
        view
        override
        onlyWhitelistedToken(_token)
        returns (Types.ReservedAmount memory)
    {
        return gamesVault[_game].reservedAmount[_token];
    }

    /** @dev returns reserve limit by game and token addresses
     * @param _game address of game contract
     * @param _token address of onw of whitelisted tokens
     */
    function getReserveLimit(
        address _game,
        address _token
    ) external view override returns (uint256) {
        return _getReserveLimit(_game, _token);
    }

    /** @dev returns max possible payout by game and token addresses
     * @param _game address of game contract
     * @param _token address of one of whitelisted tokens
     */
    function getMaxPayout(
        address _game,
        address _token
    ) external view override returns (uint256) {
        return _getMaxPayout(_game, _token);
    }

    /** @dev returns min possible wager by game and token addresses
     * @param _game address of game contract
     * @param _token address of onw of whitelisted tokens
     */
    function getMinWager(
        address _game,
        address _token
    ) external view override onlyWhitelistedToken(_token) returns (uint256) {
        return gamesVault[_game].reservedAmount[_token].minWager;
    }
}

