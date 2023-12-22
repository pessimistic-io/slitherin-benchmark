// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.1;

import "./ERC20_IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

import "./IPixelMushrohmAuthority.sol";
import "./IPixelMushrohmERC721.sol";
import "./IPixelMushrohmStaking.sol";
import "./PixelMushrohmAccessControlled.sol";

contract PixelMushrohmStaking is IPixelMushrohmStaking, PixelMushrohmAccessControlled, ReentrancyGuard {
    /* ========== DEPENDENCIES ========== */

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    uint256 public constant WEEK = 7 days;
    /// @dev unix timestamp
    uint256 public lastRewardTimestamp;
    uint256 public totalMushrohmsStaked;

    IPixelMushrohmERC721 public pixelMushrohm;

    /// @dev 9 decimals
    mapping(uint256 => StakedTokenData) public stakedTokenData;

    address private _paymentToken;
    uint256 private _stakingPrice;
    uint256 private _levelUpPrice;

    /* ========== MODIFIERS ========== */

    modifier onlyPixelMushrohm() {
        require(msg.sender == address(pixelMushrohm), "Staking: !pixelMushrohm");
        _;
    }

    modifier onlyPixelMushrohmOwner(uint256 _tokenId) {
        require(pixelMushrohm.ownerOf(_tokenId) == msg.sender, "Staking: only owner can stake");
        _;
    }

    modifier staked(uint256 _tokenId, bool expectedStaked) {
        require(isStaked(_tokenId) == expectedStaked, "Staking: wrong staked status");
        _;
    }

    modifier updateTotalMushrohmsStaked(bool isStaking) {
        lastRewardTimestamp = block.timestamp;
        if (isStaking) {
            totalMushrohmsStaked = totalMushrohmsStaked.add(1);
        } else {
            totalMushrohmsStaked = totalMushrohmsStaked.sub(1);
        }
        _;
    }

    /* ======== CONSTRUCTOR ======== */

    constructor(address _authority) PixelMushrohmAccessControlled(IPixelMushrohmAuthority(_authority)) {}

    /* ======== ADMIN FUNCTIONS ======== */

    function setPixelMushrohm(address _pixelMushrohm) external override onlyOwner {
        pixelMushrohm = IPixelMushrohmERC721(_pixelMushrohm);
        emit PixelMushrohmSet(_pixelMushrohm);
    }

    function setPaymentToken(address _tokenAddr) external override onlyOwner {
        _paymentToken = _tokenAddr;
    }

    function setStakingPrice(uint256 _price) external override onlyOwner {
        _stakingPrice = _price;
    }

    function setLevelUpPrice(uint256 _price) external override onlyOwner {
        _levelUpPrice = _price;
    }

    function inPlaceSporePowerUpdate(uint256 _tokenId) external override onlyPixelMushrohm {
        if (isStaked(_tokenId)) {
            require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
            pixelMushrohm.updateSporePower(_tokenId, sporePowerEarned(_tokenId));
            stakedTokenData[_tokenId].timestampStake = block.timestamp;
        }
    }

    function withdraw(address _tokenAddr, uint256 _amount) external override onlyVault {
        require(_tokenAddr != address(0), "PixelMushrohm: Invalid token address");
        IERC20(_tokenAddr).safeTransferFrom(address(this), msg.sender, _amount);
        emit Withdraw(_tokenAddr, _amount, msg.sender);
    }

    /* ======== MUTABLE FUNCTIONS ======== */

    function stake(uint256 _tokenId)
        external
        override
        whenNotPaused
        nonReentrant
        onlyPixelMushrohmOwner(_tokenId)
        staked(_tokenId, false)
        updateTotalMushrohmsStaked(true)
    {
        require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
        require(
            !pixelMushrohm.isLevelMaxed(_tokenId) || !pixelMushrohm.isSporePowerMaxed(_tokenId),
            "PixelMushrohm: Cannot stake maxed out token"
        );

        if (_paymentToken != address(0) && _stakingPrice != 0) {
            IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _stakingPrice);
        }

        stakedTokenData[_tokenId].timestampStake = block.timestamp;
        stakedTokenData[_tokenId].timestampLevel = block.timestamp;
        emit Staked(_tokenId);
    }

    function unstake(uint256 _tokenId)
        external
        override
        whenNotPaused
        nonReentrant
        onlyPixelMushrohmOwner(_tokenId)
        staked(_tokenId, true)
        updateTotalMushrohmsStaked(false)
    {
        pixelMushrohm.updateSporePower(_tokenId, sporePowerEarned(_tokenId));
        pixelMushrohm.updateLevelPower(_tokenId, levelPowerEarned(_tokenId));
        stakedTokenData[_tokenId].timestampStake = 0;
        stakedTokenData[_tokenId].timestampLevel = 0;
        emit Unstaked(_tokenId);
    }

    function levelUp(uint256 _tokenId) external override whenNotPaused nonReentrant onlyPixelMushrohmOwner(_tokenId) {
        require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
        require(isEligibleForLevelUp(_tokenId), "PixelMushrohm: Not eligible for a level up");

        if (_paymentToken != address(0) && _levelUpPrice != 0) {
            IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _levelUpPrice);
        }

        pixelMushrohm.updateLevel(_tokenId);
        if (stakedTokenData[_tokenId].timestampLevel != 0) {
            stakedTokenData[_tokenId].timestampLevel = block.timestamp;
        }
    }

    /* ======== VIEW FUNCTIONS ======== */

    function getPaymentToken() public view override returns (address) {
        return _paymentToken;
    }

    function getStakingPrice() public view override returns (uint256) {
        return _stakingPrice;
    }

    function getLevelUpPrice() public view override returns (uint256) {
        return _levelUpPrice;
    }

    function sporePowerEarned(uint256 _tokenId) public view override returns (uint256) {
        require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
        if (stakedTokenData[_tokenId].timestampStake == 0 || pixelMushrohm.isSporePowerMaxed(_tokenId)) return 0;
        uint256 timeDelta = block.timestamp.sub(stakedTokenData[_tokenId].timestampStake);
        return
            (
                (
                    pixelMushrohm.getSporePowerPerWeek(_tokenId).mul(timeDelta).mul(
                        pixelMushrohm
                            .getLevelMultiplier(_tokenId)
                            .add(pixelMushrohm.getAdditionalMultiplier(_tokenId))
                            .add(1e9)
                    )
                ).div(1e9)
            ).div(WEEK);
    }

    function levelPowerEarned(uint256 _tokenId) public view override returns (uint256) {
        require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
        if (stakedTokenData[_tokenId].timestampLevel == 0 || pixelMushrohm.isLevelPowerMaxed(_tokenId)) return 0;
        if (pixelMushrohm.getLevel(_tokenId) >= pixelMushrohm.getMaxLevel()) return 0;
        uint256 timeDelta = block.timestamp.sub(stakedTokenData[_tokenId].timestampLevel);
        return (levelPerWeek(_tokenId).mul(timeDelta).div(WEEK));
    }

    function levelPerWeek(uint256 _tokenId) public view override returns (uint256) {
        require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
        return pixelMushrohm.getSporePowerPerWeek(_tokenId).div(pixelMushrohm.getMaxSporePowerLevel());
    }

    function isStaked(uint256 _tokenId) public view override returns (bool) {
        return stakedTokenData[_tokenId].timestampStake > 0;
    }

    function isEligibleForLevelUp(uint256 _tokenId) public view override returns (bool) {
        require(address(pixelMushrohm) != address(0), "PixelMushrohm: Invalid pixelMushrohm address");
        require(pixelMushrohm.getLevel(_tokenId) < pixelMushrohm.getMaxLevel(), "PixelMushrohm: Already max level");
        return pixelMushrohm.getLevelPower(_tokenId) >= pixelMushrohm.getLevelCost();
    }
}

