//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// Structs
import {EpochData, MaxStrikesRange, Checkpoint, OptionsPurchase, DepositPosition, EpochRewards, MaxStrike} from "./AtlanticPutsPoolStructs.sol";

// Enums
import {OptionsState, EpochState, Contracts, VaultConfig} from "./AtlanticPutsPoolEnums.sol";

contract AtlanticPutsPoolState {
    uint256 internal constant PURCHASE_FEES_KEY = 0;
    uint256 internal constant FEE_BPS_PRECISION = 10000000;
    uint256 internal constant PRICE_ORACLE_DECIMALS = 30;

    /// @dev Options amounts precision
    uint256 internal constant OPTION_TOKEN_DECIMALS = 18;

    /// @dev Number of decimals for max strikes
    uint256 internal constant STRIKE_DECIMALS = 8;

    /// @dev Max strike weights divisor/multiplier
    uint256 internal constant WEIGHTS_MUL_DIV = 1e18;

    uint256 public currentEpoch;

    uint256 public purchasePositionsCounter = 1;
    
    uint256 public depositPositionsCounter = 0;

    mapping(VaultConfig => uint256) public vaultConfig;
    mapping(Contracts => address) public addresses;
    mapping(uint256 => EpochData) internal _epochData;
    mapping(uint256 => EpochRewards) internal _epochRewards;
    mapping(uint256 => DepositPosition) internal _depositPositions;
    mapping(uint256 => OptionsPurchase) internal _optionsPositions;

    /**
     * @notice Checkpoints for a max strike in a epoch
     * @dev    epoch => max strike => Checkpoint[]
     */
    mapping(uint256 => mapping(uint256 => MaxStrike))
        internal epochMaxStrikeCheckpoints;

    mapping(uint256 => mapping(uint256 => uint256))
        internal epochMaxStrikeCheckpointsLength;

    /**
     *  @notice Start index of checkpoint (reference point to
     *           loop from on _squeeze())
     *  @dev    epoch => index
     */
    mapping(uint256 => mapping(uint256 => uint256))
        internal epochMaxStrikeCheckpointStartIndex;

    event EmergencyWithdraw(address sender);

    event Bootstrap(uint256 epoch);

    event NewDeposit(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        address user,
        address sender
    );

    event NewPurchase(
        uint256 epoch,
        uint256 purchaseId,
        uint256 premium,
        uint256 fee,
        address user,
        address sender
    );

    event Withdraw(
        uint256 depositId,
        address receiver,
        uint256 withdrawableAmount,
        uint256 borrowFees,
        uint256 premium,
        uint256 underlying,
        uint256[] rewards
    );

    event EpochRewardsSet(uint256 epoch, uint256 amount, address rewardToken);

    event Unwind(uint256 epoch, uint256 strike, uint256 amount, address caller);

    event UnlockCollateral(
        uint256 epoch,
        uint256 totalCollateral,
        address caller
    );

    event NewSettle(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 pnl
    );

    event RelockCollateral(
        uint256 epoch,
        uint256 strike,
        uint256 totalCollateral,
        address caller
    );

    event AddressSet(Contracts _type, address _address);

    event EpochExpired(address sender);

    event VaultConfigSet(VaultConfig _type, uint256 _config);

    error AtlanticPutsPoolError(uint256 errorCode);
}

