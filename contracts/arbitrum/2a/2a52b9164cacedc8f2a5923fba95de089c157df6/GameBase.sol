//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Gameable.sol";
import "./Userable.sol";
import "./IUserManager.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC721Enumerable.sol";

abstract contract GameBase is
    Gameable,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    Game[] public games;
    Tier[] public tiers;

    mapping(uint256 => uint256[]) public gamesOfTokenID;
    mapping(TierType => uint256) public currentTiers;

    uint256 public tokenIDBotA;
    uint256 public tokenIDBotB;
    uint256 public lastGameLaunched;
    Userable public userManager;

    mapping(uint256 => mapping(uint256 => NumberChosen)) public playersOf;

    modifier claimable(uint256 tokenID, uint256 gameID) {
        require(gameID > 0, "The game not start");
        Game memory game = games[gameID];
        require(_gameIsOver(game), "The game is not over");
        require(game.winner == tokenID, "The token is not the winner");
        require(game.pool > 0, "token id has claim the price");
        _;
    }

    event PlayGame(
        uint256 indexed gameID,
        uint256 indexed tokenID,
        TierType category
    );
    event NewGame(
        uint256 indexed gameID,
        uint256 indexed tokenID,
        TierType category
    );

    function initialize() public initializer {
        __Ownable_init();
        __Pausable_init();
        Tier memory tier0 = Tier({
            category: TierType.SOUL,
            duration: 3 minutes,
            amount: 1 ether,
            maxPlayer: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isActive: true
        });
        Tier memory tier1 = Tier({
            category: TierType.MUTANT,
            duration: 3 minutes,
            amount: 3 ether,
            maxPlayer: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isActive: true
        });
        Tier memory tier2 = Tier({
            category: TierType.BORED,
            duration: 3 minutes,
            amount: 10 ether,
            maxPlayer: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isActive: true
        });
        tiers.push(tier0);
        tiers.push(tier1);
        tiers.push(tier2);
        tokenIDBotA = 0;
        tokenIDBotB = 1000000;
        _init();
    }

    function _init() internal virtual {}

    function getGame(
        uint256 gameID
    ) public view virtual override returns (Game memory) {
        require(gameID > 0, "Gameable: The game not exist");
        return games[gameID];
    }

    function getTier(
        TierType category
    ) public view virtual override returns (Tier memory) {
        for (uint256 i; i < tiers.length; i++) {
            Tier memory tier = tiers[i];
            if (tier.category == category) {
                return tier;
            }
        }
        revert("Not found");
    }

    function setTier(Tier memory tier) external virtual onlyOwner {
        int256 indexOf = -1;
        for (uint256 i; i < tiers.length; i++) {
            if (tiers[i].category == tier.category) {
                indexOf = int256(i);
            }
        }
        if (indexOf >= 0) {
            Tier storage storedTier = tiers[uint256(indexOf)];
            storedTier.duration = tier.duration;
            storedTier.amount = tier.amount;
            storedTier.maxPlayer = tier.maxPlayer;
            storedTier.isActive = tier.isActive;
            storedTier.updatedAt = block.timestamp;
        }
    }

    function setTokenIDBot(uint256 botA, uint256 botB) external onlyOwner {
        tokenIDBotA = botA;
        tokenIDBotB = botB;
    }

    function _gameIsOver(
        Game memory game
    ) internal view virtual returns (bool) {
        return block.timestamp >= game.endedAt;
    }

    function _tokenIDExistsIn(
        uint256 gameID,
        uint256 tokenID
    ) internal view returns (bool) {
        for (uint i = 0; i < games[gameID].playersInGame; i++) {
            if (playersOf[gameID][i].tokenID == tokenID) {
                return true;
            }
        }
        return false;
    }

    function getGamesOf(
        uint256 tokenID
    ) external view override returns (Game[] memory) {
        uint256[] memory gameIds = gamesOfTokenID[tokenID];
        Game[] memory gamesOf = new Game[](gameIds.length);
        for (uint256 i; i < gameIds.length; i++) {
            gamesOf[i] = games[gameIds[i]];
        }
        return gamesOf;
    }

    function getPlayersInGame(
        uint256 gameID
    ) public view virtual returns (Player[] memory) {
        Player[] memory players = new Player[](games[gameID].playersInGame);
        for (uint256 i = 0; i < games[gameID].playersInGame; i++) {
            NumberChosen memory nbChosen = playersOf[gameID][i];
            Userable.UserDescription
                memory userDescriptor = _getUserDescription(nbChosen.tokenID);
            players[i] = Player({
                tokenID: nbChosen.tokenID,
                name: userDescriptor.name,
                categoryPlayer: uint256(userDescriptor.category),
                initialBalance: userDescriptor.initialBalance,
                currentBalance: userDescriptor.balance,
                createdAt: nbChosen.createdAt,
                number: nbChosen.number
            });
        }
        return players;
    }

    function sizeGameOf(
        uint256 tokenID
    ) external view virtual returns (uint256) {
        return gamesOfTokenID[tokenID].length;
    }

    function sizeGames() external view virtual returns (uint256) {
        return games.length;
    }

    function setUserManager(address newUserManager) external virtual onlyOwner {
        userManager = Userable(newUserManager);
    }

    function claimPrice(
        uint256 tokenID,
        uint256 gameID
    ) public virtual claimable(tokenID, gameID) {
        Game storage game = games[gameID];
        userManager.credit(tokenID, game.pool);
        game.pool = 0;
        game.updatedAt = block.timestamp;
    }

    function claimAllPrice() external virtual {
        address currentAddress = msg.sender;
        uint256 balance = IERC721Enumerable(address(userManager)).balanceOf(
            currentAddress
        );
        if (balance > 0) {
            for (uint256 i = 0; i < balance; i++) {
                uint256 tokenID = IERC721Enumerable(address(userManager))
                    .tokenOfOwnerByIndex(currentAddress, i);
                uint256[] memory gameIDs = gamesOfTokenID[tokenID];
                for (uint256 j = 0; j < gameIDs.length; j++) {
                    uint256 gameID = gameIDs[j];
                    if (
                        _gameIsOver(games[gameID]) &&
                        games[gameID].pool > 0 &&
                        games[gameID].winner == tokenID
                    ) {
                        claimPrice(tokenID, gameID);
                    }
                }
            }
        }
    }

    function getTiers() external view returns (Tier[] memory) {
        return tiers;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getActivePlayersBy(
        TierType categroy
    ) external view returns (Player[] memory) {
        Player[] memory players;
        if (currentTiers[categroy] <= 0) {
            return players;
        }
        uint256 gameId = currentTiers[categroy];
        if (_gameIsOver(games[gameId])) {
            return players;
        }
        return getPlayersInGame(gameId);
    }

    function getCurrentGame(
        TierType categroy
    )
        external
        view
        returns (
            uint256 gameID,
            uint256 pool,
            uint256 startedAt,
            Player[] memory players
        )
    {
        gameID = currentTiers[categroy];
        if (gameID > 0) {
            Game memory game = getGame(gameID);
            pool = game.pool;
            startedAt = game.startedAt;
            players = getPlayersInGame(gameID);
        }
    }

    function getGameResult(
        uint256 gameID
    )
        external
        view
        virtual
        returns (uint256 winner, uint256[] memory numbers, uint256 pool)
    {
        if (gameID > 0) {
            Game memory game = games[gameID];
            numbers = new uint256[](game.playersInGame);
            pool = game.pool;
            for (uint i = 0; i < numbers.length; i++) {
                numbers[i] = playersOf[gameID][i].number;
            }
            winner = game.winner;
        }
    }

    function _getUserDescription(
        uint256 tokenID
    ) internal view virtual returns (Userable.UserDescription memory) {
        if (tokenID != tokenIDBotA && tokenID != tokenIDBotB) {
            return userManager.getUserDescription(tokenID);
        }
        Userable.UserDescription memory userDescriptor;
        userDescriptor.name = "The Reapers";
        userDescriptor.initialBalance = 0;
        userDescriptor.balance = 0;
        userDescriptor.category = IUserManager.AprType.BORED;
        return userDescriptor;
    }
}

