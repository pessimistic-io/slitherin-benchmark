// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./Initializable.sol";
import "./IController.sol";
import "./ITradeManager.sol";
import "./IUserManager.sol";
import "./UnlimitedOwnable.sol";

/**
 * @custom:member Struct to store the daily volumes of a user. Packed in 40-bit words to optimize storage.
 * @custom:member zero word 1
 * @custom:member one word 2
 * @custom:member two word 3
 * @custom:member three word 4
 * @custom:member four word 5
 * @custom:member five word 6
 */
struct DailyVolumes {
    uint40 zero;
    uint40 one;
    uint40 two;
    uint40 three;
    uint40 four;
    uint40 five;
}

/**
 * @notice Struct to store the volume limits to reach a new fee tier
 * @custom:member volume 1 The volume limit to reach the first fee tier.
 * @custom:member volume 2 The volume limit to reach the second fee tier.
 * @custom:member volume 3 The volume limit to reach the third fee tier.
 * @custom:member volume 4 The volume limit to reach the fourth fee tier.
 * @custom:member volume 5 The volume limit to reach the fifth fee tier.
 * @custom:member volume 6 The volume limit to reach the sixth fee tier.
 */
struct FeeVolumes {
    uint40 volume1;
    uint40 volume2;
    uint40 volume3;
    uint40 volume4;
    uint40 volume5;
    uint40 volume6;
}

/**
 * @notice Struct to store the fee sizes for each fee tier
 *
 * @custom:member baseFee The base fee for the base fee tier.
 * @custom:member fee1 The fee size for the first fee tier.
 * @custom:member fee2 The fee size for the second fee tier.
 * @custom:member fee3 The fee size for the third fee tier.
 * @custom:member fee4 The fee size for the fourth fee tier.
 * @custom:member fee5 The fee size for the fifth fee tier.
 * @custom:member fee6 The fee size for the sixth fee tier.
 */
struct FeeSizes {
    uint8 baseFee;
    uint8 fee1;
    uint8 fee2;
    uint8 fee3;
    uint8 fee4;
    uint8 fee5;
    uint8 fee6;
}

/**
 * @notice Struct to store the fee tiers of a specific user individually
 * @custom:member tier the tier of the user
 * @custom:member validUntil the timestamp until the tier is valid
 */
struct ManualUserTier {
    Tier tier;
    uint32 validUntil;
}

contract UserManager is IUserManager, UnlimitedOwnable, Initializable {
    /* ========== CONSTANTS ========== */

    /// @notice Maximum fee size that can be set is 1%. 0.01% - 1%
    uint256 private constant MAX_FEE_SIZE = 1_00;

    /// @notice Defines number of days in a `DailyVolumes` struct.
    uint256 public constant DAYS_IN_WORD = 6;

    /// @notice This address is used when the user has no referrer
    address private constant NO_REFERRER_ADDRESS = address(type(uint160).max);

    /* ========== STATE VARIABLES ========== */

    /// @notice Controller contract.
    IController public immutable controller;

    /// @notice TradeManager contract.
    ITradeManager public immutable tradeManager;

    /// @notice Contains user traded volume for each day.
    mapping(address => mapping(uint256 => DailyVolumes)) public userDailyVolumes;

    /// @notice Defines mannualy set tier for a user.
    mapping(address => ManualUserTier) public manualUserTiers;

    /// @notice User referrer.
    mapping(address => address) private _userReferrer;

    /// @notice Defines fee size for volume.
    FeeSizes public feeSizes;

    /// @notice Defines volume for each tier.
    FeeVolumes public feeVolumes;

    // Storage gap
    uint256[50] __gap;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the UserManager contract.
     *
     * @param unlimitedOwner_ Unlimited owner contract.
     * @param controller_ Controller contract.
     */
    constructor(IUnlimitedOwner unlimitedOwner_, IController controller_, ITradeManager tradeManager_)
        UnlimitedOwnable(unlimitedOwner_)
    {
        controller = controller_;
        tradeManager = tradeManager_;
    }

    /**
     * @notice Initializes the data.
     */
    function initialize(uint8[7] memory feeSizes_, uint32[6] memory feeVolumes_) public onlyOwner initializer {
        require(feeSizes_.length == 7, "UserManager::initialize: Bad fee sizes array length");
        require(feeVolumes_.length == 6, "UserManager::initialize: Bad fee volumes array length");

        _setFeeSize(0, feeSizes_[0]);

        for (uint256 i; i < feeVolumes_.length; ++i) {
            _setFeeVolume(i + 1, feeVolumes_[i]);
            _setFeeSize(i + 1, feeSizes_[i + 1]);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Gets users open and close position fee.
     * @dev The fee is based on users last 30 day volume.
     *
     * @param user_ user address
     * @return fee size in BPS
     */
    function getUserFee(address user_) external view returns (uint256) {
        Tier userTier = getUserTier(user_);

        FeeSizes memory _feeSizes = feeSizes;
        uint256 userFee;

        if (userTier == Tier.ZERO) {
            userFee = _feeSizes.baseFee;
        } else {
            if (userTier == Tier.ONE) {
                userFee = _feeSizes.fee1;
            } else if (userTier == Tier.TWO) {
                userFee = _feeSizes.fee2;
            } else if (userTier == Tier.THREE) {
                userFee = _feeSizes.fee3;
            } else if (userTier == Tier.FOUR) {
                userFee = _feeSizes.fee4;
            } else if (userTier == Tier.FIVE) {
                userFee = _feeSizes.fee5;
            } else {
                userFee = _feeSizes.fee6;
            }

            // if base fee is lower, use base fee (e.g. if there is a discount on fee)
            if (userFee > _feeSizes.baseFee) {
                userFee = _feeSizes.baseFee;
            }
        }

        return userFee;
    }

    /**
     * @notice Gets users fee tier.
     * @dev The fee is the bigger tier of the volume tier or manualy set one.
     *
     * @param user_ user address
     * @return userTier fee tier of the user
     */
    function getUserTier(address user_) public view returns (Tier userTier) {
        userTier = getUserVolumeTier(user_);
        Tier userManualTier = getUserManualTier(user_);

        if (userTier < userManualTier) {
            userTier = userManualTier;
        }
    }

    /**
     * @notice Gets users fee tier based on volume.
     * @dev The fee is based on users last 30 day volume.
     *
     * @param user_ user address
     * @return Tier fee tier of the user
     */
    function getUserVolumeTier(address user_) public view returns (Tier) {
        uint256 user30dayVolume = getUser30DaysVolume(user_);

        FeeVolumes memory _feeVolumes = feeVolumes;

        if (user30dayVolume < _feeVolumes.volume1) {
            return Tier.ZERO;
        }

        if (user30dayVolume < _feeVolumes.volume2) {
            return Tier.ONE;
        }

        if (user30dayVolume < _feeVolumes.volume3) {
            return Tier.TWO;
        }

        if (user30dayVolume < _feeVolumes.volume4) {
            return Tier.THREE;
        }

        if (user30dayVolume < _feeVolumes.volume5) {
            return Tier.FOUR;
        }

        if (user30dayVolume < _feeVolumes.volume6) {
            return Tier.FIVE;
        }

        return Tier.SIX;
    }

    /**
     * @notice Gets users fee manual tier.
     *
     * @param user_ user address
     * @return Tier fee tier of the user
     */
    function getUserManualTier(address user_) public view returns (Tier) {
        if (manualUserTiers[user_].validUntil >= block.timestamp) {
            return manualUserTiers[user_].tier;
        } else {
            return Tier.ZERO;
        }
    }

    /**
     * @notice Gets users last 30 days traded volume.
     *
     * @param user_ user address
     * @return user30dayVolume users last 30 days volume
     */
    function getUser30DaysVolume(address user_) public view returns (uint256 user30dayVolume) {
        for (uint256 i; i < 30; ++i) {
            (uint256 index, uint256 position) = _getPastIndexAndPosition(i);
            uint256 userDailyVolume = _getUserDailyVolume(user_, index, position);

            unchecked {
                user30dayVolume += userDailyVolume;
            }
        }
    }

    /**
     * @notice Gets the referrer of the user.
     *
     * @param user_ user address
     * @return referrer adress of the refererrer
     */
    function getUserReferrer(address user_) external view returns (address referrer) {
        referrer = _userReferrer[user_];

        if (referrer == NO_REFERRER_ADDRESS) {
            referrer = address(0);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Sets the referrer of the user. Referrer can only be set once. Of referrer is null, the user will be set
     * to NO_REFERRER_ADDRESS.
     *
     * @param user_ address of the user
     * @param referrer_ address of the referrer
     */
    function setUserReferrer(address user_, address referrer_) external onlyTradeManager {
        require(user_ != referrer_, "UserManager::setUserReferrer: User cannot be referrer");
        if (_userReferrer[user_] == address(0)) {
            if (referrer_ == address(0)) {
                _userReferrer[user_] = NO_REFERRER_ADDRESS;
            } else {
                _userReferrer[user_] = referrer_;
            }

            emit UserReferrerAdded(user_, referrer_);
        }
    }

    /**
     * @notice Adds user volume to total daily traded when new position is open.
     * @dev
     *
     * Requirements:
     * - The caller must be a valid trade pair
     *
     * @param user_ user address
     * @param volume_ volume to add
     */
    function addUserVolume(address user_, uint40 volume_) external onlyValidTradePair(msg.sender) {
        (uint256 index, uint256 position) = _getTodaysIndexAndPosition();
        _addUserDailyVolume(user_, index, position, volume_);

        emit UserVolumeAdded(user_, msg.sender, volume_);
    }

    /**
     * @notice Sets users manual tier including valid time.
     * @dev
     *
     * Requirements:
     * - The caller must be a controller
     *
     * @param user user address
     * @param tier tier to set
     * @param validUntil unix time when the manual tier expires
     */
    function setUserManualTier(address user, Tier tier, uint32 validUntil) external onlyOwner {
        manualUserTiers[user] = ManualUserTier(tier, validUntil);

        emit UserManualTierUpdated(user, tier, validUntil);
    }

    /**
     * @notice Sets fee sizes for a tier.
     * @dev
     * `feeIndexes` start with 0 as the base fee and increase by 1 for each tier.
     *
     * Requirements:
     * - The caller must be a controller
     * - `feeIndexes` and `feeSizes` must be of same length
     *
     * @param feeIndexes Index of feeSizes to update
     * @param feeSizes_ Fee sizes in BPS
     */
    function setFeeSizes(uint256[] calldata feeIndexes, uint8[] calldata feeSizes_) external onlyOwner {
        require(feeIndexes.length == feeSizes_.length, "UserManager::setFeeSizes: Array lengths don't match");

        for (uint256 i; i < feeIndexes.length; ++i) {
            _setFeeSize(feeIndexes[i], feeSizes_[i]);
        }
    }

    /**
     * @notice Sets minimum volume for a fee tier.
     * @dev
     * `feeIndexes` start with 1 as the tier one and increment by one.
     *
     * Requirements:
     * - The caller must be a controller
     * - `feeIndexes` and `feeVolumes_` must be of same length
     *
     * @param feeIndexes Index of feeVolumes_ to update
     * @param feeVolumes_ Fee volume for an index
     */
    function setFeeVolumes(uint256[] calldata feeIndexes, uint32[] calldata feeVolumes_) external onlyOwner {
        require(feeIndexes.length == feeVolumes_.length, "UserManager::setFeeVolumes: Array lengths don't match");

        for (uint256 i; i < feeIndexes.length; ++i) {
            _setFeeVolume(feeIndexes[i], feeVolumes_[i]);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Adds volume to users daily volume.
     */
    function _addUserDailyVolume(address user, uint256 index, uint256 position, uint40 volume) private {
        DailyVolumes storage userDayVolume = userDailyVolumes[user][index];

        if (position == 0) {
            userDayVolume.zero += volume;
        } else if (position == 1) {
            userDayVolume.one += volume;
        } else if (position == 2) {
            userDayVolume.two += volume;
        } else if (position == 3) {
            userDayVolume.three += volume;
        } else if (position == 4) {
            userDayVolume.four += volume;
        } else {
            userDayVolume.five += volume;
        }
    }

    /**
     * @dev Returns users daily volume.
     */
    function _getUserDailyVolume(address user, uint256 index, uint256 position) private view returns (uint256) {
        DailyVolumes storage userDayVolume = userDailyVolumes[user][index];

        if (position == 0) {
            return userDayVolume.zero;
        } else if (position == 1) {
            return userDayVolume.one;
        } else if (position == 2) {
            return userDayVolume.two;
        } else if (position == 3) {
            return userDayVolume.three;
        } else if (position == 4) {
            return userDayVolume.four;
        } else {
            return userDayVolume.five;
        }
    }

    /**
     * @dev Returns todays index and position.
     */
    function _getTodaysIndexAndPosition() private view returns (uint256, uint256) {
        return _getTimeIndexAndPosition(block.timestamp);
    }

    /**
     * @dev Returns index and position for a point of time that is "saysInThePast" days away from now.
     */
    function _getPastIndexAndPosition(uint256 daysInThePast) private view returns (uint256, uint256) {
        unchecked {
            uint256 pastDate = block.timestamp - (daysInThePast * 1 days);
            return _getTimeIndexAndPosition(pastDate);
        }
    }

    /**
     * @dev Gets index and position for a point of time.
     */
    function _getTimeIndexAndPosition(uint256 timestamp) private pure returns (uint256 index, uint256 position) {
        unchecked {
            uint256 daysFromUnix = timestamp / 1 days;

            index = daysFromUnix / DAYS_IN_WORD;
            position = daysFromUnix % DAYS_IN_WORD;
        }
    }

    /**
     * @dev Sets fee size for an index.
     */
    function _setFeeSize(uint256 feeIndex, uint8 feeSize) private {
        require(feeSize <= MAX_FEE_SIZE, "UserManager::_setFeeSize: Fee size is too high");

        if (feeIndex == 0) {
            feeSizes.baseFee = feeSize;
        } else if (feeIndex == 1) {
            feeSizes.fee1 = feeSize;
        } else if (feeIndex == 2) {
            feeSizes.fee2 = feeSize;
        } else if (feeIndex == 3) {
            feeSizes.fee3 = feeSize;
        } else if (feeIndex == 4) {
            feeSizes.fee4 = feeSize;
        } else if (feeIndex == 5) {
            feeSizes.fee5 = feeSize;
        } else if (feeIndex == 6) {
            feeSizes.fee6 = feeSize;
        } else {
            revert("UserManager::_setFeeSize: Invalid fee index");
        }

        emit FeeSizeUpdated(feeIndex, feeSize);
    }

    /**
     * @dev Sets fee volume for an index.
     */
    function _setFeeVolume(uint256 feeIndex, uint32 feeVolume) private {
        if (feeIndex == 1) {
            feeVolumes.volume1 = feeVolume;
        } else if (feeIndex == 2) {
            feeVolumes.volume2 = feeVolume;
        } else if (feeIndex == 3) {
            feeVolumes.volume3 = feeVolume;
        } else if (feeIndex == 4) {
            feeVolumes.volume4 = feeVolume;
        } else if (feeIndex == 5) {
            feeVolumes.volume5 = feeVolume;
        } else if (feeIndex == 6) {
            feeVolumes.volume6 = feeVolume;
        } else {
            revert("UserManager::_setFeeVolume: Invalid fee index");
        }

        emit FeeVolumeUpdated(feeIndex, feeVolume);
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    /**
     * @dev Reverts if TradePair is not valid.
     */
    function _onlyValidTradePair(address tradePair) private view {
        require(controller.isTradePair(tradePair), "UserManager::_onlyValidTradePair: Trade pair is not valid");
    }

    /**
     * @dev Reverts when sender is not the TradeManager
     */
    function _onlyTradeManager() private view {
        require(msg.sender == address(tradeManager), "UserManager::_onlyTradeManager: only TradeManager");
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev Reverts if TradePair is not valid.
     */
    modifier onlyValidTradePair(address tradePair) {
        _onlyValidTradePair(tradePair);
        _;
    }

    /**
     * @dev Verifies that TradeManager sent the transaction
     */
    modifier onlyTradeManager() {
        _onlyTradeManager();
        _;
    }
}

