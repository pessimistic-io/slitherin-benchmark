// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";

import "./IRandomizer.sol";
import "./IScratchGames.sol";
import "./ISupraRouter.sol";

contract VRFController is ISupraRouter, Ownable {
    IRandomizer public randomizer;

    mapping(address => bool) public isGame;
    mapping(uint256 => address) public requestIdToGame;
    mapping(uint256 => uint256) public requestIdToRngCount;

    uint256 public callbackGasLimit = 4e6;

    event Requested(uint256 id);
    event Callback(uint256 id, bytes32 value);

    constructor(address _randomizer) {
        randomizer = IRandomizer(_randomizer);
    }

    function setRandomizer(address _randomizer) external onlyOwner {
        randomizer = IRandomizer(_randomizer);
    }

    function addGame(address _game) external onlyOwner {
        require(!isGame[_game], "VRFController: Game already added");
        isGame[_game] = true;
    }

    function removeGame(address _game) external onlyOwner {
        require(isGame[_game], "VRFController: Game not added");
        isGame[_game] = false;
    }

    function generateRequest(
        string memory,
        uint8 _rngCount,
        uint256
    ) external returns (uint256) {
        require(
            address(randomizer) != address(0),
            "VRFController: Randomizer not set"
        );
        require(isGame[msg.sender], "VRFController: Not a game");
        uint256 id = randomizer.request(callbackGasLimit);
        requestIdToGame[id] = msg.sender;
        requestIdToRngCount[id] = _rngCount;
        emit Requested(id);
        return id;
    }

    function randomizerCallback(uint256 id, bytes32 value) external {
        require(msg.sender == address(randomizer), "Caller not Randomizer");
        require(
            requestIdToGame[id] != address(0),
            "VRFController: Invalid request ID"
        );
        uint256[] memory rngList = new uint256[](requestIdToRngCount[id]);
        for (uint256 i = 0; i < requestIdToRngCount[id]; i++) {
            rngList[i] = uint256(keccak256(abi.encodePacked(value, i)));
        }
        IScratchGames(requestIdToGame[id]).endMint(id, rngList);
        emit Callback(id, value);
    }

    function withdrawTo(address _to, uint256 _amount) external onlyOwner {
        randomizer.clientWithdrawTo(_to, _amount);
    }
}

