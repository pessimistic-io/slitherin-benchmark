// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./Ownable.sol";
import "./SmolBodies.sol";

contract Gym is Ownable {
    uint256 public constant WEEK = 7 days;
    /// @dev 18 decimals
    uint256 public platesPerWeek;
    /// @dev 18 decimals
    uint256 public totalPlatesStored;
    /// @dev unix timestamp
    uint256 public lastRewardTimestamp;
    uint256 public smolBodiesSupply;

    SmolBodies public smolBodies;

    mapping(uint256 => uint256) public timestampJoined;

    event JoinGym(uint256 tokenId);
    event DropGym(uint256 tokenId, uint256 plates, uint256 level);
    event SetPlatesPerWeek(uint256 platesPerWeek);
    event SmolBodiesSet(address smolBodies);

    modifier onlySmolBodyOwner(uint256 _tokenId) {
        require(smolBodies.ownerOf(_tokenId) == msg.sender, "Gym: only owner can send to gym");
        _;
    }

    modifier atGym(uint256 _tokenId, bool expectedAtGym) {
        require(isAtGym(_tokenId) == expectedAtGym, "Gym: wrong gym attendance");
        _;
    }

    modifier updateTotalPlates(bool isJoining) {
        if (smolBodiesSupply > 0) {
            totalPlatesStored = totalPlates();
        }
        lastRewardTimestamp = block.timestamp;
        isJoining ? smolBodiesSupply++ : smolBodiesSupply--;
        _;
    }

    function totalPlates() public view returns (uint256) {
        uint256 timeDelta = block.timestamp - lastRewardTimestamp;
        return totalPlatesStored + smolBodiesSupply * platesPerWeek * timeDelta / WEEK;
    }

    function platesEarned(uint256 _tokenId) public view returns (uint256 plates) {
        if (timestampJoined[_tokenId] == 0) return 0;
        uint256 timedelta = block.timestamp - timestampJoined[_tokenId];
        plates = platesPerWeek * timedelta / WEEK;
    }

    function isAtGym(uint256 _tokenId) public view returns (bool) {
        return timestampJoined[_tokenId] > 0;
    }

    function join(uint256 _tokenId)
        external
        onlySmolBodyOwner(_tokenId)
        atGym(_tokenId, false)
        updateTotalPlates(true)
    {
        timestampJoined[_tokenId] = block.timestamp;
        emit JoinGym(_tokenId);
    }

    function drop(uint256 _tokenId)
        external
        onlySmolBodyOwner(_tokenId)
        atGym(_tokenId, true)
        updateTotalPlates(false)
    {
        smolBodies.gymDrop(_tokenId, platesEarned(_tokenId));
        timestampJoined[_tokenId] = 0;

        uint256 _plates = smolBodies.musclez(_tokenId);
        uint256 _level = smolBodies.getLevel(_tokenId);
        
        emit DropGym(_tokenId, _plates, _level);
    }

    // ADMIN

    function setSmolBodies(address _smolBodies) external onlyOwner {
        smolBodies = SmolBodies(_smolBodies);
        emit SmolBodiesSet(_smolBodies);
    }

    /// @param _platesPerWeek Number of plate points to earn a week, 18 decimals
    function setPlatesPerWeek(uint256 _platesPerWeek) external onlyOwner {
        platesPerWeek = _platesPerWeek;
        emit SetPlatesPerWeek(_platesPerWeek);
    }
}

