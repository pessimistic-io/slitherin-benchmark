// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";

import "./IScratchGames.sol";
import "./ISupraRouterV2.sol";

contract VRFControllerV2 is Ownable {
    ISupraRouterContract internal supraRouter;

    mapping(address => bool) public isGame;
    mapping(uint256 => address) public requestIdToGame;
    mapping(uint256 => uint256) public requestIdToRngCount;

    event Requested(uint256 id);
    event Callback(uint256 id, uint256[] value);

    uint256 public numberOfConfirmations = 1;
    address public wlAddress;

    constructor(address _supraRouter, address _wlAddress) {
        supraRouter = ISupraRouterContract(_supraRouter);
        wlAddress = _wlAddress;
    }

    function setRandomizer(address _supraRouter) external onlyOwner {
        supraRouter = ISupraRouterContract(_supraRouter);
    }

    function setNumberOfConfirmations(
        uint256 _numberOfConfirmations
    ) external onlyOwner {
        numberOfConfirmations = _numberOfConfirmations;
    }

    function setWhitelist(address _wlAddress) external onlyOwner {
        wlAddress = _wlAddress;
    }

    function addGame(address _game) external onlyOwner {
        require(!isGame[_game], "VRFController: Game already added");
        isGame[_game] = true;
    }

    function removeGame(address _game) external onlyOwner {
        require(isGame[_game], "VRFController: Game not added");
        isGame[_game] = false;
    }

    function generateRequest(uint8 _rngCount) external returns (uint256) {
        require(
            address(supraRouter) != address(0),
            "VRFController: Randomizer not set"
        );
        require(isGame[msg.sender], "VRFController: Not a game");
        uint256 id = supraRouter.generateRequest(
            "randomizerCallback(uint256,uint256[])",
            _rngCount,
            numberOfConfirmations,
            wlAddress
        );
        requestIdToGame[id] = msg.sender;
        requestIdToRngCount[id] = _rngCount;
        emit Requested(id);
        return id;
    }

    function randomizerCallback(
        uint256 id,
        uint256[] calldata values
    ) external {
        require(msg.sender == address(supraRouter), "Caller not SupraRouter");
        require(
            requestIdToGame[id] != address(0),
            "VRFController: Invalid request ID"
        );
        uint256[] memory rngList = new uint256[](requestIdToRngCount[id]);
        for (uint256 i = 0; i < requestIdToRngCount[id]; i++) {
            rngList[i] = values[i];
        }
        IScratchGames(requestIdToGame[id]).endMint(id, rngList);
        emit Callback(id, rngList);
    }
}

