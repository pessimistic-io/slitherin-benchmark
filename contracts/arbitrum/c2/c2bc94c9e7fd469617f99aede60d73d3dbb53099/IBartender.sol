//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";


/* ##################################################################
                            STRUCTS
################################################################## */
struct UserDepositInfo {
    // Amount in supply as debt to SAKE
    uint256 amount;
    // max withdrawal amount
    uint256 maxWithdrawalAmount;
    uint256 totalWithdrawn;
    // store user shares
    uint256 shares;
    // track user withdrawal
    uint256 initializedShareStates;
}

struct UpdatedDebtRatio {
    uint256 newValue;
    uint256 newDebt;
    uint256 newRatio;
}

struct SakeVaultInfo {
    bool isLiquidated;
    // total amount of USDC use to purchase VLP
    uint256 leverage;
    // record total amount of VLP
    uint256 totalAmountOfVLP;
    uint256 totalAmountOfVLPInUSDC;
    // get all deposited without leverage
    uint256 totalAmountOfUSDCWithoutLeverage;
    // store puchase price of VLP
    uint256 purchasePrice;
    // store all users in array
    address[] users;
    // store time when the sake vault is created
    uint256 startTime;
}

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Factory and global config params
 */
interface IBartender {
    /* ##################################################################
                                EVENTS
    ################################################################## */
    /**
     * @dev Emitted when new `sake` contract is created by the keeper
     * with it `associatedTime`
     */
    event CreateNewSAKE(address indexed sake, uint256 indexed associatedTime);
    /**
     * @dev Emitted when new `supply` is provided and is required to be updated with `value`
     */
    event SettingManager(bytes32 supply, address value);
    /**
     * @dev Emitted when new `supply` is provided and is required to be updated with `value`
     */
    event SettingManagerForBool(bytes32 supply, bool value);

    /**
     * @dev Emitted when new `supply` is required to be updated with `value`
     */
    event SettingManagerForTripleSlope(bytes32 supply, uint256 value);

    /**
     * @dev Emitted when user deposited into the vault
     * `user` is the msg.sender
     * `amountDeposited` is the amount user deposited
     * `associatedTime` the time at which the deposit is made
     * `leverageFromWater` how much leverage was taking by the user from the WATER VAULT
     */
    event BartenderDeposit(
        address indexed user,
        uint256 amountDeposited,
        uint256 indexed associatedTime,
        uint256 indexed leverageFromWater
    );
    /**
     * @dev Emitted when user withdraw from the vault
     * `user` is the msg.sender
     * `amount` is the amount user withdraw
     * `sakeId` the id that identify each sake
     * `withdrawableAmountInVLP` how much vlp was taking and been sold for USDC
     */
    event Withdraw(
        address indexed user,
        uint256 indexed amount,
        uint256 sakeId,
        uint256 indexed withdrawableAmountInVLP
    );
    /**
     * @dev Emitted when there is need to update protocol fee
     * `feeEnabled` state of protocol fee
     */
    event ProtocolFeeStatus(bool indexed feeEnabled);
    /* ##################################################################
                                CUSTOM ERRORS
    ################################################################## */
    /// @notice Revert when caller is not SAKE
    error BTDNotSAKE();

    /// @notice Revert when caller is not Admin
    error BTDNotAKeeper();

    /// @notice Revert when caller is not Liquor
    error BTDNotLiquor();

    /// @notice Revert when input amount is zero
    error ThrowZeroAmount();

    /// @notice Revert when sake vault is liquidated
    error ThrowLiquidated();
    /// @notice Revert when New SAKE is not successfully created
    error UnsuccessfulCreationOfSake();

    /// @notice Revert when there is no deposit and new SAKE want to be created.
    error CurrentDepositIsZero();

    /// @notice Revert when invalid parameter is supply during
    error InvalidParameter(bytes32);

    /// @notice Revert set fee is greated than maximum fee (MAX_BPS)
    error InvalidFeeBps();

    /// @notice Revert when protocol fee is already in the current state of fee
    // error FeeAlreadySet();

    /// @notice Invalid address provided
    error ThrowZeroAddress();

    /// @notice Revert when lock time is on
    error ThrowLockTimeOn();

    /// @notice Revert when amount supplied is greater than locked amount
    error ThrowInvalidAmount();

    /// @notice Revert when amount supplied is greater than locked amount
    error SakeWitdrawal(address sake, uint256 amount);

    /// @notice Revert when the utilization ratio is greater than optimal utilization
    error ThrowOptimalUtilization();

    /// @dev When the value is greater than `MAX_BPS`
    error ThrowInvalidValue();

    /// @dev available params: `optimalUtilization`, `maxFeeSplitSlope1`,
    /// `maxFeeSplitSlope2`, `maxFeeSplitSLope3`, `utilizationThreshold1`,
    /// `utilizationThreshold2`, `utilizationThreshold3`
    /// @param params takes the bytes32 params name
    /// @param value takes the uint256 params value
    error ThrowInvalidParameter(bytes32 params, uint256 value);

    /// @notice deposit USDC into the Vault
    /// Requirements:
    /// {caller: anyone}.
    /// `_amount` it must be greater than 0.
    ///  user must have approve Bartender contract to spend USDC and allowance must be greater than `_amount`
    /// @param _amount amount in USDC msg.sender want to deposit to take leverage.
    /// @param _receiver recipient of $BARTENDER!.
    function deposit(uint256 _amount, address _receiver) external;

    /// @notice withdraw locked USDC from Vault
    /// Requirements:
    /// {caller: anyone}.
    /// `_amount` it must be greater than 0.
    /// `_amount` it must be less than amountDeposited.
    ///  withdrawal time must exceed numbers of time required to withdraw.
    ///  48 hours leverage must
    /// @param _amount amount in USDC msg.sender want to withdraw.
    /// @param _receiver address to recieve the `amount`.
    function withdraw(uint256 _amount, uint256 id, address _receiver) external;

    /// @notice gety current Id of BARTENDER! that has been minted
    /// @return uint256
    function getCurrentId() external view returns (uint256);

    function getSakeVaultInfo(uint256 id) external view returns (SakeVaultInfo memory);

    function depositInfo(uint256 id, address user) external view returns (UserDepositInfo memory);

    function getDebtInfo(uint256 id) external view returns (UpdatedDebtRatio memory);

    function getSakeAddress(uint256 id) external view returns (address);

    function setLiquidated(uint256 id) external returns (address sakeAddress);

    function getFeeStatus() external view returns (address, bool, uint96);
}

