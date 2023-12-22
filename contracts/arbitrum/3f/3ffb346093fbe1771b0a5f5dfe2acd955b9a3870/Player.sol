/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./IPlayer.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20BackwardsCompatible.sol";
import "./Types.sol";

contract Player is IPlayer, Ownable, ReentrancyGuard {
    error OnlyXPSource(address _caller);
    error OnlyAvatarUnlocker(address _caller);
    error OnlyHouse(address _caller);
    error AlreadyInitialized();
    error LevelTooLow(uint256 _level, uint256 _minLevel);
    error UsernameTaken(string _username);
    error InvalidUsername();
    error AvatarLocked(uint256 _avatar);
    error ReferralAlreadySet();

    mapping (address => Types.Player) players;
    mapping (uint256 => uint256) levels;

    mapping (address => uint256) level;
    mapping (address => uint256) xp;
    mapping (address => address) referral;
    mapping (address => bool) xpSources;
    mapping (address => bool) avatarUnlockers;
    mapping (string => bool) usernameTaken;
    mapping (address => mapping (uint256 => bool)) avatarUnlocked; 

    IERC20BackwardsCompatible public immutable usdt;
    IERC20BackwardsCompatible public immutable sarc;
    IERC20BackwardsCompatible public immutable xarc;
    address public house;

    event LevelUp(address indexed _account, uint256 indexed _level, uint256 indexed _timestamp);

    bool private initialized;

    modifier onlyXPSource() {
        if (!xpSources[msg.sender]) {
            revert OnlyXPSource(msg.sender);
        }
        _;
    }

    modifier onlyAvatarUnlocker() {
        if (!avatarUnlockers[msg.sender]) {
            revert OnlyAvatarUnlocker(msg.sender);
        }
        _;
    }

    modifier onlyHouse() {
        if (msg.sender != house) {
            revert OnlyHouse(msg.sender);
        }
        _;
    }

    constructor (address _USDT, address _sARC, address _xARC) {
        usdt = IERC20BackwardsCompatible(_USDT);
        sarc = IERC20BackwardsCompatible(_sARC);
        xarc = IERC20BackwardsCompatible(_xARC);
    }

    function initialize(address _house) external onlyOwner {
        if (initialized) {
            revert AlreadyInitialized();
        }
        uint256 _total = 0;
        for (uint256 _i = 0; _i < 101; _i++) {
            _total += (100 * _i);
            levels[_i] = _total; // defines xp threshold for each level
        }
        house = _house;

        initialized = true;
    }

    function getVIPTier(address _account) external view returns (uint256) {
        uint256 _vip;
        uint256 _sarcBalance = sarc.balanceOf(_account);
        uint256 _xarcBalance = xarc.balanceOf(_account);
        uint256 _level = level[_account];
        if (_sarcBalance >= 2000 ether || _xarcBalance >= 1000 ether || _level >= 45) {
            if (_sarcBalance >= 80000 ether || _xarcBalance >= 40000 ether || _level == 100) {
                _vip = 4;
            } else if (_sarcBalance >= 15000 ether || _xarcBalance >= 7500 ether || _level >= 70) {
                _vip = 3;
            } else if (_sarcBalance >= 6000 ether || _xarcBalance >= 3000 ether || _level >= 50) {
                _vip = 2;
            } else {
                _vip = 1;
            }
        }
        return _vip;
    }

    function _receiveXP(address _account, uint256 _xp) private {
        xp[_account] += _xp;
        if (level[_account] == 100) {
            return;
        }
        for (uint256 _i = level[_account]; _i < 101; _i++) {
            if (xp[_account] >= levels[_i]) {
                if (_i > level[_account]) {
                    _levelUp(_account, _i);
                }
            } else {
                break;
            }
        }
    }

    function _levelUp(address _account, uint256 _level) private {
        /*
        Level 3 - Unlock daily spin
        Level 5 - Unlock weekly spin
        */
        level[_account] = _level;
        emit LevelUp(_account, _level, block.timestamp);
    }

    function setUsername(string memory _username) external nonReentrant {
        if (level[msg.sender] < 3) {
            revert LevelTooLow(level[msg.sender], 3);
        }
        if (usernameTaken[_username]) {
            revert UsernameTaken(_username);
        }
        if (keccak256(abi.encodePacked(_username)) == keccak256(abi.encodePacked(""))) {
            revert InvalidUsername();
        }
        Types.Player storage _player = players[msg.sender];
        usernameTaken[_player.username] = false;
        _player.username = _username;
        usernameTaken[_player.username] = true;
        players[msg.sender] = _player;
    }

    function setAvatar(uint256 _avatar) external nonReentrant {
        if (avatarUnlocked[msg.sender][_avatar]) {
            revert AvatarLocked(_avatar);
        }
        Types.Player storage _player = players[msg.sender];
        _player.avatar = _avatar;
        players[msg.sender] = _player;
    }

    function setReferral(address _account, address _referral) external onlyHouse nonReentrant {
        if (referral[_account] != address(0)) {
            revert ReferralAlreadySet();
        }
        referral[_account] = _referral;
    }

    function unlockAvatar(address _account, uint256 _avatar) external nonReentrant onlyAvatarUnlocker {
        avatarUnlocked[_account][_avatar] = true;
    }

    function giveXP(address _account, uint256 _xp) external nonReentrant onlyXPSource {
        _receiveXP(_account, _xp);
    }

    function addXPSource(address _xpSource) external nonReentrant onlyOwner {
        xpSources[_xpSource] = true;
    }

    function addAvatarUnlocker(address _avatarUnlocker) external nonReentrant onlyOwner {
        avatarUnlockers[_avatarUnlocker] = true;
    }

    function getProfile(address _account) external view returns (Types.Player memory, uint256) {
        return (players[_account], usdt.balanceOf(_account));
    }

    function getLevel(address _account) external view returns (uint256) {
        return level[_account];
    }

    function getXp(address _account) external view returns (uint256) {
        return xp[_account];
    }

    function getReferral(address _account) external view returns (address) {
        return referral[_account];
    }

    receive() external payable {}
}

