// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IConsole.sol";
import "./IGame.sol";
import "./IRNG.sol";
import "./IVault.sol";
import "./CoreUpgradeable.sol";

abstract contract GameUpgradeable is
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    CoreUpgradeable,
    IGame
{
    /*==================================================== Errors ====================================================*/

    error InvalidGas(uint256 _gas);
    error InvalidData();
    error RNGUnauthorized(address _caller);
    error NotPlayer(address _caller);
    error NotRefundableYet();

    /*==================================================== Events ====================================================*/

    event GameSessionCreated(bytes32 _requestId);

    event GameSessionPlayed(
        address indexed _user,
        uint256 indexed _gameId,
        string _gameName,
        address _frontendReferral,
        uint256 _startTime,
        uint256 _wager,
        address _token,
        uint256 _payoutAmount,
        uint256 _sentValue,
        uint8 _autoRollAmount,
        bytes _gameData,
        uint256[] _randomValue
    );

    /*==================================================== State Variables ====================================================*/

    uint256 public id;
    address public gameProvider;
    uint32 public refundCooldown; // default value
    IConsole public console;
    IVault public vault;
    IRNG public rng;
    mapping(bytes32 => bool) public completedGames;

    uint256 public constant PERCENT_VALUE = 10000;

    string public gameName;

    /*==================================================== Modifiers ==========================================================*/

    modifier checkGasPerRoll() {
        uint256 gasPerRoll_ = console.getGasPerRoll();
        if (gasPerRoll_ > msg.value) {
            revert InvalidGas(msg.value);
        }
        (bool success, ) = payable(address(rng)).call{value: gasPerRoll_}("");
        require(success, "Transfer failed.");
        _;
    }

    modifier onlyRNG() {
        if (msg.sender != address(rng)) {
            revert RNGUnauthorized(msg.sender);
        }
        _;
    }

    modifier isGameCountAcceptable(uint8 _gameCount) {
        require(0 < _gameCount && _gameCount <= 100, "GAME: count out-range");
        _;
    }

    modifier whenNotCompleted(bytes32 _requestId) {
        require(!completedGames[_requestId], "GAME: completed");
        completedGames[_requestId] = true;
        _;
    }

    modifier incId() {
        id++;
        _;
    }

    /*==================================================== Functions ===========================================================*/

    /** @dev Creates a contract.
     * @param _console Root caller of that contract.
     * @param _rng the callback contract
     * @param _vault the vault contract
     * @param _gameProvider the game provider royalty address
     * @param _gameName the game name, to ease backend parse
     */
    function __Game_init(
        address _console,
        address _rng,
        address _vault,
        address _gameProvider,
        string memory _gameName
    ) public payable onlyInitializing {
        __Core_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        id++;
        refundCooldown = 2 hours; // default value
        rng = IRNG(_rng);
        gameProvider = _gameProvider;
        console = IConsole(_console);
        vault = IVault(_vault);
        gameName = _gameName;
    }

    /** @dev edits console address
     * @param _console *
     */
    function editConsole(address _console) external override onlyGovernance {
        console = IConsole(_console);
    }

    /** @dev edits vault address
     * @param _vault *
     */
    function editVault(address _vault) external override onlyGovernance {
        vault = IVault(_vault);
    }

    /** @dev edits rng address
     * @param _rng *
     */
    function editRNG(address _rng) external override onlyGovernance {
        rng = IRNG(_rng);
    }

    /** @dev edits game provider address
     * @param _gameProvider *
     */
    function editGameProvider(
        address _gameProvider
    ) external override onlyGovernance {
        gameProvider = _gameProvider;
    }

    /** @dev pauses contract if possible, locks play()
     */
    function pause() external override onlyGovernance {
        _pause();
        if (_isContract(address(console))) {
            console.editGamePauseStatus(true);
        }
    }

    /** @dev unpauses contract if possible, unlocks play()
     */
    function unpause() external override onlyGovernance {
        _unpause();
        if (_isContract(address(console))) {
            console.editGamePauseStatus(false);
        }
    }

    /** @dev Plays a game called. Requires to be overriden in game contract
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _wager Amount that was initially sent.
     * @param _autoRollAmount Amount of games in a call.
     * @param _gameData *
     */
    function play(
        address _token,
        address _frontendReferral,
        uint8 _autoRollAmount,
        uint256 _wager,
        bytes memory _gameData
    ) external payable virtual override {}

    /** @dev function to refund uncompleted game wagers
     * @param _requestId *
     */
    function refundGame(bytes32 _requestId) external virtual override {}

    /** @dev Fulfilling game, can be called only by RNG. Requires to be overriden in game contract
     * @param _requestId *
     * @param _randomWords *
     */
    function fulfill(
        bytes32 _requestId,
        uint256[] memory _randomWords
    ) external virtual {
        _fulfill(_requestId, _randomWords);
    }

    /*==================================================== Internal Functions ===========================================================*/

    /** @dev basic create func to reduce code
     * @param _token one of whitelisted tokens
     * @param _autoRollAmount amount of games in a call
     * @param _toReserve amount to reserve for winning
     * @param _sentAmount wager amount
     */
    function _createBasic(
        address _token,
        uint8 _autoRollAmount,
        uint256 _toReserve,
        uint256 _sentAmount
    ) internal returns (bytes32) {
        vault.depositReservedAmount(
            _token,
            _msgSender(),
            _sentAmount,
            _autoRollAmount,
            id,
            _toReserve
        );

        return rng.makeRequestUint256Array(_autoRollAmount);
    }

    /** @dev Fulfilling game, can be called only by RNG
     * @param _requestId *
     * @param _randomWords *
     */
    function _fulfill(
        bytes32 _requestId,
        uint256[] memory _randomWords
    ) internal virtual;

    /*==================================================== View Functions ===========================================================*/

    /** @dev returns id
     */
    function getId() external view override returns (uint256) {
        return id;
    }

    /** @dev returns console address
     */
    function getConsole() external view override returns (address) {
        return address(console);
    }

    /** @dev returns whether game is paused or not
     */
    function isPaused() external view override returns (bool) {
        return paused();
    }

    /** @dev returns rng address
     */
    function getRng() external view override returns (address) {
        return address(rng);
    }

    /** @dev returns vault address
     */
    function getVault() external view override returns (address) {
        return address(vault);
    }

    /** @dev returns whether request id is unfulfuilled
     */
    function getGameProvider() external view override returns (address) {
        return gameProvider;
    }

    /** @dev returns whether game is completed
     * @param _requestId *
     */
    function getcompletedGames(
        bytes32 _requestId
    ) external view override returns (bool) {
        return completedGames[_requestId];
    }
}

