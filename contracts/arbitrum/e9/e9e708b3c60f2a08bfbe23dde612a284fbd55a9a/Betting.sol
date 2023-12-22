// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Random.sol";

/**
 * @title Owner
 * @dev Set & change owner
 */
contract Betting is Random {
    enum Result {
        NOT_PLAYED,
        A,
        B
    }

    struct Game {
        address playerA;
        address playerB;
        uint256 bet;
        uint256 id;
        Result result;
        uint256 timestamp;
    }

    Game[] games;

    uint256 id_counter;
    uint256 private houseCut;
    uint256 private houseBalance;
    address tokenAddress;
    bool allowNewGames;

    event NewGame(Game game);
    event FinishedGame(Game game);
    event NewHouseCut(uint256 cut);
    event AllowNewGamesChanged(bool allowe);
    event GameRemoved(Game game);

    constructor() {
        id_counter = 1;
        tokenAddress = 0x1C91234D38c93b294828D2DDB6313a0e09053D46;
        houseCut = 1;
        allowNewGames = true;

        nodes = [0x989586c30452d28113F30613973E30e29f4986dD]; /*Oracle wallet*/
    }

    function claimHouseBalance(uint256 _amount) external onlyOwner {
        require(
            _amount <= getHouseBalance(),
            "You are trying to withdraw more than the balance!"
        );
        ERC20(tokenAddress).transfer(msg.sender, getHouseBalance());
    }

    function getHouseBalance() public view onlyOwner returns (uint256) {
        uint256 ballance = ERC20(tokenAddress).balanceOf(address(this));
        for (uint256 i = 0; i < games.length; ++i) {
            ballance -= games[i].bet;
        }
        return ballance;
    }

    function getGameAt(uint256 id) internal view returns (Game memory g) {
        for (uint256 i = 0; i < games.length; i++) {
            if (games[i].id == id) {
                return games[i];
            }
        }
        require(false, "No game with that id");
    }

    function getIndexOf(uint256 id) internal view returns (uint256 ret) {
        for (uint256 i = 0; i < games.length; i++) {
            if (games[i].id == id) {
                return i;
            }
        }
        require(false, "No game with that id");
    }

    function getGames() external view returns (Game[] memory) {
        return games;
    }

    function getIDCounter() external view returns (uint256) {
        return id_counter;
    }

    function getHouseCut() external view returns (uint256) {
        return houseCut;
    }

    function setHouseCut(uint256 cut) external onlyOwner {
        houseCut = cut;
        emit NewHouseCut(cut);
    }

    function remove(uint256 index) internal {
        require(index < games.length);
        games[index] = games[games.length - 1];
        games.pop();
    }

    function bet(uint256 amount, bool isOnA) external {
        require(allowNewGames, "This game is currently disabled.");
        Game memory g;
        g.bet = amount;
        g.id = id_counter;
        g.result = Result.NOT_PLAYED;
        g.timestamp = block.timestamp;
        ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        if (isOnA) {
            g.playerA = msg.sender;
        } else {
            g.playerB = msg.sender;
        }
        games.push(g);
        ++id_counter;
        emit NewGame(g);
    }

    function finishGame(uint256 id) external {
        uint256 index = getIndexOf(id);
        require(
            games[index].result == Result.NOT_PLAYED,
            "Game already played!"
        );
        require(
            games[index].playerA != address(0) ||
                games[index].playerB != address(0),
            "Missing first player!"
        );
        bool ok = true;
        ok =
            ok &&
            ERC20(tokenAddress).transferFrom(
                msg.sender,
                address(this),
                games[index].bet
            );

        if (games[index].playerA == address(0)) {
            games[index].playerA = msg.sender;
        } else {
            games[index].playerB = msg.sender;
        }
        require(ok, "Sending bet founds failed");
        requestRandomNumber(games[index].id);
    }

    function reciveRandomNumber(uint256 id, uint256 number) internal override {
        uint256 index = getIndexOf(id);
        require(
            games[index].result == Result.NOT_PLAYED,
            "Game already played!"
        );
        bool ok = true;
        if (number % 2 == 0) {
            // player A wins
            games[index].result = Result.A;
            ok =
                ok &&
                ERC20(tokenAddress).transfer(
                    games[index].playerA,
                    (games[index].bet * 2 * (100 - houseCut)) / 100
                );
        } else {
            //player B wins
            games[index].result = Result.B;
            ok =
                ok &&
                ERC20(tokenAddress).transfer(
                    games[index].playerB,
                    (games[index].bet * 2 * (100 - houseCut)) / 100
                );
        }
        require(ok, "Sending winning founds failed");
        emit FinishedGame(games[index]);
        remove(index);
    }

    function setAllowNewGames(bool allow) external onlyOwner {
        allowNewGames = allow;
        emit AllowNewGamesChanged(allow);
    }

    function getAllowNewGames() external view returns (bool) {
        return allowNewGames;
    }

    function unbet(uint256 id) external {
        uint256 index = getIndexOf(id);
        address playerOne;
        if (games[index].playerA == address(0)) {
            playerOne = games[index].playerB;
        } else {
            playerOne = games[index].playerA;
        }
        require(
            ((playerOne == msg.sender &&
                (games[index].timestamp + 24 * 60 * 60 < block.timestamp)) ||
                owner() == msg.sender),
            "Not allowed to remove the game"
        );
        ERC20(tokenAddress).transfer(
            playerOne,
            (games[index].bet * (100 - houseCut)) / 100
        );
        emit GameRemoved(games[index]);
        remove(index);
    }
}

