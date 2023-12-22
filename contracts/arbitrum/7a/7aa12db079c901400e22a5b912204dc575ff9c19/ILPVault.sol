//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Interfaces
import {IERC20} from "./IERC20.sol";
import {OneInchZapLib} from "./OneInchZapLib.sol";

interface ILPVault {
    enum VaultType {
        BULL,
        BEAR
    }

    enum UserStatus {
        NOT_ACTIVE,
        ACTIVE,
        EXITING,
        FLIPPING
    }

    // Token being deposited
    function depositToken() external view returns (IERC20);

    // Flag to see if any funds have been borrowed this epoch
    function borrowed() external view returns (bool);

    function cap() external view returns (uint256);

    function totalDeposited() external view returns (uint256);

    function getUserStatus(address _user) external view returns (UserStatus);

    function deposit(address _user, uint256 _amount) external;

    // ============================= Events ================================

    /**
     * @notice Emitted when a address deposits
     * @param _from The address that makes the deposit
     * @param _to The address that receives a balance
     * @param _amount The amount that was deposited
     */
    event Deposited(address indexed _from, address indexed _to, uint256 _amount);

    /**
     * @notice Emitted when a user cancels a deposit
     * @param _user The address that receives a balance
     * @param _amount The amount that was deposited
     */
    event CanceledDeposit(address indexed _user, uint256 _amount);

    /**
     * @notice Emitted when a user signals a vault flip
     * @param _user The address that requested the flip
     * @param _vault The vault that is fliping to
     */
    event Flipped(address indexed _user, address indexed _vault);

    /**
     * @notice Emitted when a user signals an exit
     * @param _user The address that requested the exit
     */
    event UserSignalExit(address indexed _user);

    /**
     * @notice Emitted when a user cancels a signal exit
     * @param _user The address that requested the exit
     */
    event UserCancelSignalExit(address indexed _user);

    /**
     * @notice Emitted when a user withdraws
     * @param _user The address that withdrew
     * @param _amount the amount sent out
     */
    event Withdrew(address indexed _user, uint256 _amount);

    /**
     * @notice Emitted when epoch ends
     * @param _epoch epoch that ended
     * @param _endBalance epoch end balance
     * @param _startBalance epoch start balance
     */
    event EpochEnded(uint256 indexed _epoch, uint256 _endBalance, uint256 _startBalance);

    /**
     * @notice Emitted when epoch starts
     * @param _epoch epoch started
     * @param _startBalance epoch start balance
     */
    event EpochStart(uint256 indexed _epoch, uint256 _startBalance);

    /**
     * @notice Emitted when a strategy borrows funds from the vault
     * @param _strategy address of the strategy
     * @param _amount the amount taken
     */
    event Borrowed(address indexed _strategy, uint256 _amount);

    /**
     * @notice Emitted when a strategy repays funds to the vault
     * @param _strategy address of the strategy
     * @param _amount the amount taken
     */
    event Repayed(address indexed _strategy, uint256 _amount);

    /**
     * @notice Emitted when someone updates the risk percentage
     * @param _governor governor that ran the update
     * @param _oldRate rate before the update
     * @param _newRate rate after the update
     */
    event RiskPercentageUpdated(address indexed _governor, uint256 _oldRate, uint256 _newRate);

    /**
     * @notice Emitted when the vault is paused
     * @param _governor governor that paused the vault
     * @param _epoch final epoch
     */
    event VaultPaused(address indexed _governor, uint256 indexed _epoch);

    // ============================= Errors ================================

    error STARTING_EPOCH_BEFORE_ENDING_LAST();
    error VAULT_PAUSED();
    error EMERGENCY_OFF_NOT_PAUSED();
    error EMERGENCY_AFTER_SIGNAL();
    error TERMINAL_EPOCH_NOT_REACHED();
    error USER_EXITING();
    error USER_FLIPPING();
    error ZERO_VALUE();
    error NON_WHITELISTED_FLIP();
    error NO_DEPOSITS_FOR_USER();
    error USER_ALREADY_EXITING();
    error EPOCH_ENDED();
    error CANNOT_WITHDRAW();
    error ALREADY_BORROWED();
    error ALREADY_WHITELISTED();
    error NOT_WHITELISTED();
    error OPERATION_IN_FUTURE();
    error DEPOSITED_THIS_EPOCH();
    error INVALID_SWAP();
    error TARGET_VAULT_FULL();
    error VAULT_FULL();
    error WRONG_VAULT_ARGS();
    error ACTION_FORBIDEN_IN_USER_STATE();
    error FORBIDDEN_SWAP_RECEIVER();
    error FORBIDDEN_SWAP_SOURCE();
    error FORBIDDEN_SWAP_DESTINATION();
    error HIGH_SLIPPAGE();
    error USER_EXITING_ON_FLIP_VAULT();
    error USER_FLIPPING_ON_FLIP_VAULT();
    error CANNOT_CANCEL_EXIT();

    // ============================= Structs ================================

    struct Flip {
        uint256 userPercentage;
        address destinationVault;
    }

    struct Epoch {
        uint256 startAmount;
        uint256 endAmount;
    }

    struct UserEpochs {
        uint256[] epochs;
        uint256 end;
        uint256 deposited;
        UserStatus status;
        uint256 exitPercentage;
    }
}

interface IBearLPVault is ILPVault {
    function borrow(
        uint256[2] calldata _minTokenOutputs,
        uint256 _min2Crv,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    ) external returns (uint256[2] memory);

    function repay(
        uint256[2] calldata _minOutputs,
        uint256 _minLpTokens,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    ) external returns (uint256);
}

interface IBullLPVault is ILPVault {
    function borrow(uint256[2] calldata _minTokenOutputs) external returns (uint256);

    function repay(
        uint256 _minPairTokens,
        address[] calldata _inTokens,
        uint256[] calldata _inTokenAmounts,
        OneInchZapLib.SwapParams[] calldata _swapParams
    ) external returns (uint256);
}

