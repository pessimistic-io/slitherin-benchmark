// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC20 } from "./IERC20.sol";
import { ECDSA } from "./ECDSA.sol";

/**
 * @title Mafia Nuts staking contract
 * @author @aster2709 <https://twitter.com/aster2709>
 * @notice Stake your nut to activate nftperp protocol gamification and earn rewards!
 */
contract NutStaking is OwnableUpgradeable, PausableUpgradeable {
    /// @notice info upgrade mafia nuts
    /// @dev signed by authorizedSigner
    struct UpgradeInfo {
        uint tokenId;
        uint level;
        uint expiry;
        bytes signature;
    }
    //
    // STORAGE
    //
    IERC721 public MAFIA_NUTS;
    address public authorizedSigner;

    mapping(bytes => bool) public usedSignatures;
    mapping(address => uint) public stakerMap;
    mapping(uint256 => uint256) private _levelMap;

    //
    // EVENTS
    //
    event Deploy(address indexed deployer, uint timestamp);
    event Stake(address indexed user, uint indexed tokenId);
    event Unstake(address indexed user, uint indexed tokenId);
    event Upgrade(uint indexed tokenId, uint indexed level, bytes indexed signature);

    /**
     * @dev upgradeable constructor
     */
    function initialize(IERC721 _MAFIA_NUTS) external initializer {
        __Ownable_init();
        __Pausable_init();
        MAFIA_NUTS = _MAFIA_NUTS;
        emit Deploy(msg.sender, block.timestamp);
    }

    /**
     * @notice stake mafia nut
     * @param _tokenId token id
     */
    function stakeNut(uint _tokenId) external whenNotPaused {
        address user = msg.sender;
        uint stakedTokenId = stakerMap[user];
        require(stakedTokenId != _tokenId, "already staked");
        if (stakedTokenId != 0) {
            _unstakeNut(user, stakedTokenId);
        }
        _stakeNut(user, _tokenId);
    }

    /**
     * @notice unstake mafia nut
     * @param _tokenId token id
     */
    function unstakeNut(uint _tokenId) external whenNotPaused {
        address user = msg.sender;
        require(stakerMap[user] == _tokenId, "!staked");
        _unstakeNut(user, _tokenId);
    }

    /**
     * @notice upgrade mafia nuts to new level
     * @dev upgrade info signed by authorized signer
     */
    function upgradeToken(UpgradeInfo memory _upgradeInfo) external {
        // validation
        uint currentLevel = getLevel(_upgradeInfo.tokenId);
        require(!usedSignatures[_upgradeInfo.signature], "used sig");
        require(MAFIA_NUTS.ownerOf(_upgradeInfo.tokenId) == msg.sender, "!exist");
        require(_upgradeInfo.expiry > block.timestamp, "expired");
        require(_upgradeInfo.level > currentLevel && _upgradeInfo.level < 6, "max level");
        bytes32 message = keccak256(
            abi.encodePacked(_upgradeInfo.tokenId, _upgradeInfo.level, _upgradeInfo.expiry, block.chainid)
        );
        address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(message), _upgradeInfo.signature);
        require(signer == authorizedSigner, "HTTP 401");

        // upgrade
        usedSignatures[_upgradeInfo.signature] = true;
        _setLevel(_upgradeInfo.tokenId, _upgradeInfo.level);
        emit Upgrade(_upgradeInfo.tokenId, _upgradeInfo.level, _upgradeInfo.signature);
    }

    /**
     * @notice set authorized signer
     * @dev only owner
     */
    function setAuthorizedSigner(address _authorizedSigner) external onlyOwner {
        authorizedSigner = _authorizedSigner;
    }

    /**
     * @notice get level
     */
    function getLevel(uint256 _tokenId) public view returns (uint256) {
        return _levelMap[_tokenId] + 1;
    }

    /**
     * @notice recover stuck erc20 tokens, contact team
     * @dev only owner can call, sends tokens to owner
     */
    function recoverFT(address _token, uint _amount) external onlyOwner {
        IERC20(_token).transfer(owner(), _amount);
    }

    /**
     * @notice recover stuck erc721 tokens, contact team
     * @dev only owner can call, sends tokens to owner
     */
    function recoverNFT(address _token, uint _tokenId) external onlyOwner {
        IERC721(_token).transferFrom(address(this), owner(), _tokenId);
    }

    /**
     * @notice pause staking
     * @dev only owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice unpause staking
     * @dev only owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function _stakeNut(address _user, uint _tokenId) internal {
        stakerMap[_user] = _tokenId;
        MAFIA_NUTS.transferFrom(_user, address(this), _tokenId);
        emit Stake(_user, _tokenId);
    }

    function _unstakeNut(address _user, uint _tokenId) internal {
        delete stakerMap[_user];
        MAFIA_NUTS.transferFrom(address(this), _user, _tokenId);
        emit Unstake(_user, _tokenId);
    }

    function _setLevel(uint _tokenId, uint _level) internal {
        _levelMap[_tokenId] = _level - 1;
    }
}

