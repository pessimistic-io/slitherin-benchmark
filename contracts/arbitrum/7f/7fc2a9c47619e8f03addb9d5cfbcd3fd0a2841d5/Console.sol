// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IConsole.sol";
import "./Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Console is IConsole, Ownable {
    error GameNotFound(uint256 _id);

    mapping (uint256 => Types.Game) public games;
    mapping (address => uint256) public impls;
    uint256 public id;

    constructor () {}

    function addGame(bool _live, string memory _name, uint256 _edge, address _impl) external onlyOwner {
        Types.Game memory _game = Types.Game({
            id: id,
            live: _live,
            name: _name,
            edge: _edge,
            date: block.timestamp,
            impl: _impl
        });

        games[id] = _game;
        impls[_impl] = id;
        id ++;
    }

    function editGame(uint256 _id, bool _live, string memory _name, uint256 _edge, address _impl) external onlyOwner {
        if(games[_id].date == 0) {
            revert GameNotFound(_id);
        }

        Types.Game memory _game = Types.Game({
            id: games[_id].id,
            live: _live,
            name: _name,
            edge: _edge,
            date: block.timestamp,
            impl: _impl
        });
        games[_id] = _game;
        impls[_impl] = _id;
    }

    function getId() external view returns (uint256) {
        return id;
    }

    function getGame(uint256 _id) external view returns (Types.Game memory) {
        return games[_id];
    }

    function getGameByImpl(address _impl) external view returns (Types.Game memory) {
        return games[impls[_impl]];
    }

    function getLiveGames() external view returns (Types.Game[] memory) {
        Types.Game[] memory _games;
        uint256 _j = 0;
        for (uint256 _i = 0; _i < id; _i++) {
            Types.Game memory _game = games[_i];
            if (_game.live) {
                _games[_j] = _game;
                _j++;
            }
        }
        return _games;
    }
}
