//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IConsole.sol";
import "./IGame.sol";
import "./IRNG.sol";
import "./IVault.sol";
import "./Types.sol";
import "./CoreUpgradeable.sol";

contract ConsoleUpgradeable is CoreUpgradeable, IConsole {
    /*==================================================== Errors ====================================================*/

    error GasPerRollTooHigh(uint256 _gasPerRoll);
    error ImplementationIsInUse(address _impl);
    error GameNotFound(uint256 _id);

    /*==================================================== Events ====================================================*/

    event UpdateGame(
        uint256 id,
        string name,
        bool paused,
        uint256 date,
        address impl
    );
    event EditVault(address newAddress);
    event EditRNG(address newAddress);

    /*==================================================== State Variables ====================================================*/

    // Games
    mapping(uint256 => Types.Game) public games;
    mapping(address => uint256) public impls;
    uint256 public id;

    // Management
    uint256 public gasPerRoll;

    /*==================================================== Modifiers ===========================================================*/

    modifier onlyGame() {
        require(impls[_msgSender()] != uint256(0), "Console: Not game");
        _;
    }

    /*==================================================== Functions ===========================================================*/

    /** @dev Creates a contract
     */
    function initialize() public payable initializer {
        __Core_init();
        gasPerRoll = 10 ** 16;
        id++;
    }

    /** @dev Creates new game, sets create timestamp
     * @param _name the game name to ease search
     * @param _impl game address implementation
     */
    function addGame(
        string memory _name,
        address _impl
    ) external override onlyGovernance {
        if (impls[_impl] != uint256(0)) {
            revert ImplementationIsInUse(_impl);
        }

        Types.Game memory Game_ = Types.Game({
            id: id,
            paused: IGame(_impl).isPaused(),
            name: _name,
            date: block.timestamp,
            impl: _impl
        });
        games[id] = Game_;
        impls[_impl] = id;
        id++;

        emit UpdateGame(
            Game_.id,
            Game_.name,
            Game_.paused,
            Game_.date,
            Game_.impl
        );
    }

    /** @dev Edits existing game
     * @param _id game id
     * @param _name the game name to ease search
     * @param _impl game address implementation
     */
    function editGame(
        uint256 _id,
        string memory _name,
        address _impl
    ) external override onlyGovernance {
        if (games[_id].date == 0) {
            revert GameNotFound(_id);
        }
        Types.Game memory Game_ = Types.Game({
            id: games[_id].id,
            paused: IGame(_impl).isPaused(),
            name: _name,
            date: games[_id].date,
            impl: _impl
        });
        games[_id] = Game_;
        impls[_impl] = _id;
        emit UpdateGame(
            Game_.id,
            Game_.name,
            Game_.paused,
            Game_.date,
            Game_.impl
        );
    }

    /** @dev Edits game paused status
     * @param _value true or false
     */
    function editGamePauseStatus(bool _value) external override onlyGame {
        Types.Game memory Game_ = games[impls[_msgSender()]];
        games[Game_.id].paused = _value;
        emit UpdateGame(Game_.id, Game_.name, _value, Game_.date, Game_.impl);
    }

    /** @dev sets new gasPerRoll.
     * @param _gasPerRoll *
     */
    function setGasPerRoll(
        uint256 _gasPerRoll
    ) external override onlyGovernance {
        if (_gasPerRoll > 10 ** 16) {
            revert GasPerRollTooHigh(_gasPerRoll);
        }
        gasPerRoll = _gasPerRoll;
    }

    /*==================================================== View Functions ===========================================================*/

    /** @dev returns id
     */
    function getId() external view override returns (uint256) {
        return id;
    }

    /** @dev returns game by id search
     */
    function getGames() external view override returns (Types.Game[] memory) {
        Types.Game[] memory _Games = new Types.Game[](id -1);
        for (uint256 _i = 1; _i < id; _i++) {
            Types.Game storage _game = games[_i];
            _Games[_i - 1] = _game;
        }
        return _Games;
    }

    /** @dev returns game by id search
     * @param _id id of the implementation
     */
    function getGame(
        uint256 _id
    ) external view override returns (Types.Game memory) {
        return games[_id];
    }

    /** @dev returns game by id search, with some extra data from game and vault
     * @param _id id of the implementation
     * @param _token token address
     */
    function getGameWithExtraData(
        uint256 _id,
        address _token
    ) external view override returns (Types.GameWithExtraData memory) {
        if (games[_id].date == 0) {
            revert GameNotFound(_id);
        }

        Types.Game memory game_ = games[_id];
        IVault vault_ = IVault(IGame(game_.impl).getVault());
        uint256 minWager_ = vault_.getMinWager(game_.impl, _token);
        uint256 maxPayout_ = vault_.getMaxPayout(game_.impl, _token);
        uint256 maxReservedAmount_ = vault_.getReserveLimit(game_.impl, _token);
        Types.GameVaultReturn memory gameVault_ = vault_.getGameVault(
            game_.impl
        );
        return
            Types.GameWithExtraData({
                game: game_,
                vault: address(vault_),
                token: _token,
                minWager: minWager_,
                maxPayout: maxPayout_,
                maxReservedAmount: maxReservedAmount_,
                gameVault: gameVault_
            });
    }

    /** @dev returns game by address search
     * @param _impl address of the implementation
     */
    function getImpl(address _impl) external view override returns (uint256) {
        return impls[_impl];
    }

    /** @dev returns game by address search
     * @param _impl address of the implementation
     */
    function getGameByImpl(
        address _impl
    ) external view override returns (Types.Game memory) {
        return games[impls[_impl]];
    }

    /** @dev returns game by id search
     */
    function getGasPerRoll() external view override returns (uint256) {
        return gasPerRoll;
    }
}

