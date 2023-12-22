// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ERC721Enumerable.sol";
import "./Math.sol";
import "./Strings.sol";
import "./Counters.sol";
import "./Gym.sol";
import "./MinterControl.sol";

contract SmolBodies is MinterControl, ERC721Enumerable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    uint256 constant LAST_MALE = 3332;
    uint256 constant LAST_FEMALE = 6665;

    enum Gender { Male, Female }

    Counters.Counter private _maleTokenIdTracker;
    Counters.Counter private _femaleTokenIdTracker;
    string public baseURI;

    /// @dev 18 decimals
    uint256 public swolMaxLevel;
    /// @dev 18 decimals
    uint256 public levelPlatesCost;

    Gym public gym;

    // tokenId => Plates
    mapping(uint256 => uint256) public musclez;

    event BaseURIChanged(string from, string to);
    event SmolBodiesMint(address to, uint256 tokenId, string tokenURI);
    event LevelPlatesCost(uint256 levelPlatesCost);
    event SwolMaxLevel(uint256 swolMaxLevel);
    event GymSet(address gym);

    modifier onlyGym() {
        require(msg.sender == address(gym), "SmolBodies: !gym");
        _;
    }

    constructor() ERC721("Smol Bodies", "SmolBodies") {
        _femaleTokenIdTracker._value = LAST_MALE + 1;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, AccessControl) returns (bool) {
        return ERC721Enumerable.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    function mintMale(address _to) external onlyMinter {
        _mint(_to, Gender.Male);
    }

    function mintFemale(address _to) external onlyMinter {
        _mint(_to, Gender.Female);
    }

    function getGender(uint256 _tokenId) public pure returns (Gender) {
        return _tokenId <= LAST_MALE ? Gender.Male : Gender.Female;
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "SmolBodies: URI query for nonexistent token");

        uint256 level = getLevel(_tokenId);

        return bytes(baseURI).length > 0 ?
            string(abi.encodePacked(
                baseURI,
                _tokenId.toString(),
                "/",
                level.toString()
            ))
            : "";
    }

    function getLevel(uint256 _tokenId) public view returns (uint256 level) {
        level = Math.min(scanPlates(_tokenId) / levelPlatesCost, swolMaxLevel);
    }

    function scanPlates(uint256 _tokenId) public view returns (uint256 plates) {
        plates = musclez[_tokenId] + gym.platesEarned(_tokenId);
    }

    function averagePlates() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        uint256 totalPlates = gym.totalPlates();
        return totalPlates / totalSupply();
    }

    /// @param _tokenId tokenId of the Smol Bodies
    function gymDrop(uint256 _tokenId, uint256 _platesEarned) external onlyGym {
        musclez[_tokenId] += _platesEarned;
    }

    function _mint(address _to, Gender _gender) internal {
        uint256 _tokenId;

        if (_gender == Gender.Male) {
            _tokenId = _maleTokenIdTracker.current();
            _maleTokenIdTracker.increment();

            require(_tokenId <= LAST_MALE, "SmolBodies: exceeded tokenId for male");
        } else {
            _tokenId = _femaleTokenIdTracker.current();
            _femaleTokenIdTracker.increment();

            require(_tokenId <= LAST_FEMALE, "SmolBodies: exceeded tokenId for female");
        }

        _safeMint(_to, _tokenId);

        emit SmolBodiesMint(_to, _tokenId, tokenURI(_tokenId));
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal override {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        if (address(gym) != address(0))
            require(!gym.isAtGym(_tokenId), "SmolBodies: is at gym. Drop gym to transfer.");
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // ADMIN

    function setGym(address _gym) external onlyOwner {
        gym = Gym(_gym);
        emit GymSet(_gym);
    }

    function setLevelPlatesCost(uint256 _levelPlatesCost) external onlyOwner {
        levelPlatesCost = _levelPlatesCost;
        emit LevelPlatesCost(_levelPlatesCost);
    }

    function setMaxLevel(uint256 _swolMaxLevel) external onlyOwner {
        swolMaxLevel = _swolMaxLevel;
        emit SwolMaxLevel(_swolMaxLevel);
    }

    function setBaseURI(string memory _baseURItoSet) external onlyOwner {
        emit BaseURIChanged(baseURI, _baseURItoSet);

        baseURI = _baseURItoSet;
    }
}

