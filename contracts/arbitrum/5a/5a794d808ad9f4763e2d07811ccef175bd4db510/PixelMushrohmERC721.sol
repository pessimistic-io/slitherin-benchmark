// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.1;

import "./ERC20_IERC20.sol";
import "./introspection_IERC165.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ERC721Enumerable.sol";
import "./MerkleProof.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./Strings.sol";
import "./Counters.sol";

import "./IPixelMushrohmAuthority.sol";
import "./IPixelMushrohmERC721.sol";
import "./IPixelMushrohmStaking.sol";
import "./PixelMushrohmAccessControlled.sol";

contract PixelMushrohmERC721 is IPixelMushrohmERC721, ERC721Enumerable, PixelMushrohmAccessControlled, ReentrancyGuard {
    /* ========== DEPENDENCIES ========== */

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Strings for uint256;
    using Counters for Counters.Counter;

    /* ========== STATE VARIABLES ========== */

    bool public revealed = false;

    uint256 constant BRIDGE_MAX_MINT = 1500;
    uint256 constant APELIEN_MAX_MINT = 50;
    uint256 constant DEV_MAX_MINT = 1;
    uint256 constant FIRST_GEN_LEVEL_MAX_MINT = 1500;
    uint256 constant WHITELIST_MAX_MINT = 2030;

    mapping(address => uint256) private _numUserTokensMinted;

    Counters.Counter private _standardTokenIdTracker;
    Counters.Counter private _apelienTokenIdTracker;
    Counters.Counter private _numStandardTokensMinted;
    string public baseURI;
    string public prerevealURI;

    address private _mintToken;
    uint256 private _mintTokenPrice;
    uint256 private _maxMintPerWallet = 1;
    bytes32 public merkleRoot;

    uint256 private _maxSporePowerLevel = 4;
    uint256 private _maxLevel = 10;
    /// @dev 18 decimals
    uint256 private _sporePowerCost = 50000000000000000000;
    uint256 private _levelCost = 50000000000000000000;
    /// @dev 18 decimals
    uint256 public totalSporePower;
    /// @dev 9 decimals
    uint256 private _baseLevelMultiplier = 20000000; // 2%
    uint256 public firstGenLevelMintLevel = 2;

    IPixelMushrohmStaking public staking;
    mapping(address => bool) public redeemers;
    mapping(address => bool) public multipliers;
    address public bridge;

    mapping(uint256 => TokenData) public tokenData;
    mapping(uint256 => bool) public firstGenLevelMintComplete;

    /* ========== MODIFIERS ========== */

    modifier onlyStaking() {
        require(msg.sender == address(staking), "PixelMushrohm: !staking");
        _;
    }

    modifier onlyRedeemer() {
        require(redeemers[msg.sender], "PixelMushrohm: !redeemer");
        _;
    }

    modifier onlyBridge() {
        require(msg.sender == bridge, "PixelMushrohm: !bridge");
        _;
    }

    modifier onlyMultiplier() {
        require(multipliers[msg.sender], "PixelMushrohm: !multiplier");
        _;
    }

    /* ======== CONSTRUCTOR ======== */

    constructor(address _authority)
        ERC721("Pixel Mushrohm", "PixelMushrohm")
        PixelMushrohmAccessControlled(IPixelMushrohmAuthority(_authority))
    {}

    /* ======== ADMIN FUNCTIONS ======== */

    function setStaking(address _staking) external override onlyOwner {
        staking = IPixelMushrohmStaking(_staking);
        emit StakingSet(_staking);
    }

    function addRedeemer(address _redeemer) external override onlyOwner {
        redeemers[_redeemer] = true;
        emit RedeemerAdded(_redeemer);
    }

    function removeRedeemer(address _redeemer) external override onlyOwner {
        redeemers[_redeemer] = false;
        emit RedeemerRemoved(_redeemer);
    }

    function addMultiplier(address _multiplier) external override onlyOwner {
        multipliers[_multiplier] = true;
        emit MultiplierAdded(_multiplier);
    }

    function removeMultiplier(address _multiplier) external override onlyOwner {
        multipliers[_multiplier] = false;
        emit MultiplierRemoved(_multiplier);
    }

    function setBridge(address _bridge) external override onlyOwner {
        bridge = _bridge;
        emit BridgeSet(_bridge);
    }

    function setMaxSporePowerLevel(uint256 _max) external override onlyPolicy {
        _maxSporePowerLevel = _max;
        emit MaxSporePowerLevel(_max);
    }

    function setMaxLevel(uint256 _max) external override onlyPolicy {
        _maxLevel = _max;
        emit MaxLevel(_max);
    }

    function setBaseLevelMultiplier(uint256 _multiplier) external override onlyPolicy {
        _baseLevelMultiplier = _multiplier;
        emit BaseLevelMultiplier(_multiplier);
    }

    function setFirstGenLevelMintLevel(uint256 _level) external override onlyPolicy {
        firstGenLevelMintLevel = _level;
        emit FirstGenLevelMintLevel(_level);
    }

    function setSporePowerPerWeek(uint256 _sporePowerPerWeek, uint256[] calldata _tokenIds)
        external
        override
        onlyOwner
    {
        require(_sporePowerPerWeek > 0, "PixelMushrohm: Spore power per week must be greater than 0");
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            tokenData[_tokenIds[i]].sporePowerPerWeek = _sporePowerPerWeek;
        }
    }

    function setBaseURI(string memory _baseURItoSet) external override onlyPolicy {
        baseURI = _baseURItoSet;
    }

    function setPrerevealURI(string memory _prerevealURI) external override onlyPolicy {
        prerevealURI = _prerevealURI;
    }

    function setMintToken(address _tokenAddr) external override onlyOwner {
        _mintToken = _tokenAddr;
    }

    function setMintTokenPrice(uint256 _price) external override onlyOwner {
        _mintTokenPrice = _price;
    }

    function setMaxMintPerWallet(uint256 _maxPerWallet) external override onlyOwner {
        _maxMintPerWallet = _maxPerWallet;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external override onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function toggleReveal() external override onlyOwner {
        revealed = !revealed;
    }

    function withdraw(address _tokenAddr) external override onlyVault {
        require(_tokenAddr != address(0), "PixelMushrohm: Invalid token address");
        uint256 tokenBalance = IERC20(_tokenAddr).balanceOf(address(this));
        require(tokenBalance > 0, "PixelMushrohm: No token balance");
        IERC20(_tokenAddr).transfer(msg.sender, tokenBalance);
    }

    function manualBridgeMint(address[] calldata _to, uint256[] calldata _tokenId) external override onlyPolicy {
        require(
            _to.length == _tokenId.length,
            "PixelMushrohm: List of addresses and list of token IDs must be the same size"
        );

        for (uint256 i = 0; i < _to.length; i++) {
            require(!_exists(_tokenId[i]), "PixelMushrohm: Token already exists");
            _mint(_to[i], _tokenId[i], MintType.BRIDGE);
        }
    }

    function airdrop(
        MintType _mintType,
        address[] calldata _to,
        uint256[] calldata _amount
    ) external override onlyOwner {
        require(
            (_mintType == MintType.APELIEN_AIRDROP ||
                _mintType == MintType.NOOSH_AIRDROP ||
                _mintType == MintType.PILOT_AIRDROP ||
                _mintType == MintType.R3L0C_AIRDROP ||
                _mintType == MintType.MEMETIC_AIRDROP ||
                _mintType == MintType.STANDARD),
            "PixelMushrohm: Must be an airdrop mint type"
        );
        require(
            _to.length == _amount.length,
            "PixelMushrohm: List of addresses and list of amounts must be the same size"
        );
        for (uint256 i = 0; i < _to.length; i++) {
            for (uint256 j = 0; j < _amount[i]; j++) {
                if (_mintType == MintType.STANDARD) {
                    _numStandardTokensMinted.increment();
                    _numUserTokensMinted[_to[i]] = _numUserTokensMinted[_to[i]].add(1);
                }
                _mint(_to[i], 0, _mintType);
            }
        }
    }

    /* ======== DEBUG FUNCTIONS ======== */

    // function adjustSporePower(uint256 _tokenId, uint256 _sporePower) external override onlyOwner {
    //     uint256 _maxSporePower = _sporePowerCost.mul(_maxSporePowerLevel);
    //     if (_sporePower > _maxSporePower) {
    //         _sporePower = _maxSporePower;
    //     }

    //     if (_sporePower > tokenData[_tokenId].sporePower) {
    //         uint256 _sporePowerDiff = _sporePower.sub(tokenData[_tokenId].sporePower);
    //         totalSporePower = totalSporePower.add(_sporePowerDiff);
    //     } else {
    //         uint256 _sporePowerDiff = tokenData[_tokenId].sporePower.sub(_sporePower);
    //         totalSporePower = totalSporePower.sub(_sporePowerDiff);
    //     }

    //     tokenData[_tokenId].sporePower = _sporePower;
    // }

    // function adjustLevelPower(uint256 _tokenId, uint256 _levelPower) external override onlyOwner {
    //     if (_levelPower > _levelCost) {
    //         _levelPower = _levelCost;
    //     }
    //     tokenData[_tokenId].levelPower = _levelPower;
    // }

    // function mintFirstGen(uint256 _tokenId) external override onlyOwner {
    //     require(!_exists(_tokenId), "PixelMushrohm: Token already exists");
    //     _mint(msg.sender, _tokenId, MintType.BRIDGE);
    // }

    /* ======== MUTABLE FUNCTIONS ======== */

    function whitelistMint(uint256 _amount, bytes32[] calldata _merkleProof)
        external
        override
        whenNotPaused
        nonReentrant
    {
        require(_amount > 0, "PixelMushrohm: Amount must be greater than 0");
        require(_numStandardTokensMinted.current() < WHITELIST_MAX_MINT, "PixelMushrohm: Mint complete");
        require(_mintToken != address(0), "PixelMushrohm: Payment token not set");
        require(_mintTokenPrice != 0, "PixelMushrohm: Payment price not set");
        require(
            _numUserTokensMinted[msg.sender].add(_amount) <= _maxMintPerWallet,
            "PixelMushrohm: Max mint limit reached"
        );
        require(_isWhitelisted(msg.sender, _merkleProof), "PixelMushrohm: Not in whitelist");

        IERC20(_mintToken).safeTransferFrom(msg.sender, address(this), _mintTokenPrice.mul(_amount));

        for (uint256 i = 0; i < _amount; i++) {
            _numStandardTokensMinted.increment();
            _numUserTokensMinted[msg.sender] = _numUserTokensMinted[msg.sender].add(1);
            _mint(msg.sender, 0, MintType.STANDARD);
        }
    }

    function bridgeMint(address _to, uint256 _tokenId) external override whenNotPaused onlyBridge {
        require(!_exists(_tokenId), "PixelMushrohm: Token already exists");
        _mint(_to, _tokenId, MintType.BRIDGE);
    }

    function firstGenLevelMint(uint256 _tokenId) external override whenNotPaused nonReentrant {
        require(ownerOf(_tokenId) == msg.sender, "PixelMushrohm: Sender is not the owner of the token ID");
        require(isEligibleForLevelMint(_tokenId), "PixelMushrohm: Not eligible for level mint");
        _mint(msg.sender, 0, MintType.STANDARD);
        firstGenLevelMintComplete[_tokenId] = true;
    }

    function updateSporePower(uint256 _tokenId, uint256 _sporePowerEarned) external override whenNotPaused onlyStaking {
        uint256 maxSporePower = _sporePowerCost.mul(_maxSporePowerLevel);
        if (tokenData[_tokenId].sporePower.add(_sporePowerEarned) <= maxSporePower) {
            totalSporePower = totalSporePower.add(_sporePowerEarned);
        } else {
            uint256 result;
            (, result) = maxSporePower.trySub(tokenData[_tokenId].sporePower);
            totalSporePower = totalSporePower.add(result);
        }
        tokenData[_tokenId].sporePower = Math.min(tokenData[_tokenId].sporePower.add(_sporePowerEarned), maxSporePower);
    }

    function updateLevelPower(uint256 _tokenId, uint256 _levelPowerEarned) external override whenNotPaused onlyStaking {
        tokenData[_tokenId].levelPower = Math.min(tokenData[_tokenId].levelPower.add(_levelPowerEarned), _levelCost);
    }

    function updateLevel(uint256 _tokenId) external override whenNotPaused onlyStaking {
        require(getLevel(_tokenId) < _maxLevel, "PixelMushrohm: Level already maxxed");
        tokenData[_tokenId].levelPower = 0;
        tokenData[_tokenId].level = tokenData[_tokenId].level.add(1);
    }

    function redeemSporePower(uint256 _tokenId, uint256 _amount)
        external
        override
        whenNotPaused
        nonReentrant
        onlyRedeemer
    {
        require(_amount > 0, "PixelMushrohm: Amount must be greater than 0");

        staking.inPlaceSporePowerUpdate(_tokenId);
        require(
            _amount <= tokenData[_tokenId].sporePower,
            "PixelMushrohm: Cannot redeem more spore power than is available"
        );

        totalSporePower = totalSporePower.sub(_amount);
        tokenData[_tokenId].sporePower = tokenData[_tokenId].sporePower.sub(_amount);
        emit RedeemSporePower(_tokenId, _amount);
    }

    function setAdditionalMultiplier(uint256 _tokenId, uint256 _multiplier)
        external
        override
        whenNotPaused
        nonReentrant
        onlyMultiplier
    {
        tokenData[_tokenId].additionalMultiplier = _multiplier;
        emit AdditionalMultiplier(_tokenId, _multiplier);
    }

    /* ======== INTERNAL FUNCTIONS ======== */

    function _calculateTokenIdStartEnd(MintType _mintType) internal view returns (uint256, uint256) {
        uint256 _prevStop;

        if (_mintType == MintType.BRIDGE) {
            return (1, BRIDGE_MAX_MINT);
        } else if (_mintType == MintType.APELIEN_AIRDROP) {
            (, _prevStop) = _calculateTokenIdStartEnd(MintType.BRIDGE);
            return (_prevStop.add(1), _prevStop.add(APELIEN_MAX_MINT));
        } else if (_mintType == MintType.NOOSH_AIRDROP) {
            (, _prevStop) = _calculateTokenIdStartEnd(MintType.APELIEN_AIRDROP);
            return (_prevStop.add(1), _prevStop.add(DEV_MAX_MINT));
        } else if (_mintType == MintType.PILOT_AIRDROP) {
            (, _prevStop) = _calculateTokenIdStartEnd(MintType.NOOSH_AIRDROP);
            return (_prevStop.add(1), _prevStop.add(DEV_MAX_MINT));
        } else if (_mintType == MintType.R3L0C_AIRDROP) {
            (, _prevStop) = _calculateTokenIdStartEnd(MintType.PILOT_AIRDROP);
            return (_prevStop.add(1), _prevStop.add(DEV_MAX_MINT));
        } else if (_mintType == MintType.MEMETIC_AIRDROP) {
            (, _prevStop) = _calculateTokenIdStartEnd(MintType.R3L0C_AIRDROP);
            return (_prevStop.add(1), _prevStop.add(DEV_MAX_MINT));
        } else {
            (, _prevStop) = _calculateTokenIdStartEnd(MintType.MEMETIC_AIRDROP);
            return (_prevStop.add(1), _prevStop.add(FIRST_GEN_LEVEL_MAX_MINT).add(WHITELIST_MAX_MINT));
        }
    }

    function _mint(
        address _to,
        uint256 _tokenId,
        MintType _mintType
    ) internal {
        uint256 _tokenIdStart;
        uint256 _maxMint;
        (_tokenIdStart, _maxMint) = _calculateTokenIdStartEnd(_mintType);

        if (_mintType == MintType.APELIEN_AIRDROP) {
            _tokenId = _apelienTokenIdTracker.current().add(_tokenIdStart);
            _apelienTokenIdTracker.increment();
        } else if (
            _mintType == MintType.NOOSH_AIRDROP ||
            _mintType == MintType.PILOT_AIRDROP ||
            _mintType == MintType.R3L0C_AIRDROP ||
            _mintType == MintType.MEMETIC_AIRDROP
        ) {
            _tokenId = _tokenIdStart;
        } else if (_mintType == MintType.STANDARD) {
            _tokenId = _standardTokenIdTracker.current().add(_tokenIdStart);
            _standardTokenIdTracker.increment();
        }

        require(_tokenId <= _maxMint, "PixelMushrohm: Maximum token ID reached");

        emit PixelMushrohmMint(_to, _tokenId);
        _safeMint(_to, _tokenId);
    }

    function _isWhitelisted(address _owner, bytes32[] calldata _merkleProof) internal view returns (bool) {
        if (merkleRoot == 0) {
            return true;
        }
        bytes32 leaf = keccak256(abi.encodePacked(_owner));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        if (address(staking) != address(0))
            require(!staking.isStaked(_tokenId), "PixelMushrohm: Is staked. Unstake to transfer.");
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /* ======== VIEW FUNCTIONS ======== */

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        if (!revealed) {
            return prerevealURI;
        } else {
            require(_exists(_tokenId), "PixelMushrohm: URI query for nonexistent token");

            uint256 sporePowerLevel = getSporePowerLevel(_tokenId);
            return
                bytes(baseURI).length > 0
                    ? string(abi.encodePacked(baseURI, _tokenId.toString(), "/", sporePowerLevel.toString(), ".json"))
                    : "";
        }
    }

    function exists(uint256 _tokenId) public view override returns (bool) {
        return _exists(_tokenId);
    }

    function getMintToken() public view override returns (address) {
        return _mintToken;
    }

    function getMintTokenPrice() public view override returns (uint256) {
        return _mintTokenPrice;
    }

    function getMaxMintPerWallet() public view override returns (uint256) {
        return _maxMintPerWallet;
    }

    function getSporePower(uint256 _tokenId) public view override returns (uint256) {
        uint256 maxSporePower = _sporePowerCost.mul(_maxSporePowerLevel);
        return Math.min(tokenData[_tokenId].sporePower.add(staking.sporePowerEarned(_tokenId)), maxSporePower);
    }

    function getSporePowerLevel(uint256 _tokenId) public view override returns (uint256) {
        return Math.min(getSporePower(_tokenId).div(_sporePowerCost), _maxSporePowerLevel);
    }

    function averageSporePower() public view override returns (uint256) {
        if (totalSupply() == 0) return 0;
        return totalSporePower.div(totalSupply());
    }

    function getSporePowerCost() public view override returns (uint256) {
        return _sporePowerCost;
    }

    function getMaxSporePowerLevel() public view override returns (uint256) {
        return _maxSporePowerLevel;
    }

    function getSporePowerPerWeek(uint256 _tokenId) public view override returns (uint256) {
        return tokenData[_tokenId].sporePowerPerWeek;
    }

    function getLevel(uint256 _tokenId) public view override returns (uint256) {
        return tokenData[_tokenId].level.add(1);
    }

    function getLevelPower(uint256 _tokenId) public view override returns (uint256) {
        return Math.min(tokenData[_tokenId].levelPower.add(staking.levelPowerEarned(_tokenId)), _levelCost);
    }

    function getLevelCost() public view override returns (uint256) {
        return _levelCost;
    }

    function getMaxLevel() public view override returns (uint256) {
        return _maxLevel;
    }

    function getBaseLevelMultiplier() public view override returns (uint256) {
        return _baseLevelMultiplier;
    }

    function getLevelMultiplier(uint256 _tokenId) public view override returns (uint256) {
        return _baseLevelMultiplier.mul(tokenData[_tokenId].level);
    }

    function getAdditionalMultiplier(uint256 _tokenId) public view override returns (uint256) {
        return tokenData[_tokenId].additionalMultiplier;
    }

    function getTokenURIsForOwner(address _owner) public view override returns (string[] memory) {
        uint256 ownerBalance = balanceOf(_owner);
        string[] memory tokenURIs = new string[](ownerBalance);
        for (uint256 i = 0; i < ownerBalance; i++) {
            tokenURIs[i] = tokenURI(tokenOfOwnerByIndex(_owner, i));
        }
        return tokenURIs;
    }

    function isEligibleForLevelMint(uint256 _tokenId) public view override returns (bool) {
        return _tokenId <= 1500 && getLevel(_tokenId) >= firstGenLevelMintLevel && !firstGenLevelMintComplete[_tokenId];
    }

    function getNumTokensMinted(address _owner) public view override returns (uint256) {
        return _numUserTokensMinted[_owner];
    }

    function isSporePowerMaxed(uint256 _tokenId) public view override returns (bool) {
        uint256 maxSporePower = _sporePowerCost.mul(_maxSporePowerLevel);
        return tokenData[_tokenId].sporePower >= maxSporePower;
    }

    function isLevelPowerMaxed(uint256 _tokenId) public view override returns (bool) {
        return tokenData[_tokenId].levelPower >= _levelCost;
    }

    function isLevelMaxed(uint256 _tokenId) public view override returns (bool) {
        return getLevel(_tokenId) >= getMaxLevel();
    }

    function hasUserHitMaxMint(address _user) public view override returns (bool) {
        return _numUserTokensMinted[_user] >= _maxMintPerWallet;
    }
}

