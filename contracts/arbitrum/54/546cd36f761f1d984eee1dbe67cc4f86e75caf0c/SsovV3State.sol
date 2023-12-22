//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "./IERC20.sol";

// Structs
import {VaultCheckpoint, WritePosition, EpochStrikeData, Addresses, EpochData} from "./SsovV3Structs.sol";

abstract contract SsovV3State {
    /// @dev Manager role which handles bootstrapping
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @dev Underlying assets symbol
    string public underlyingSymbol;

    /// @notice Whether this is a Put or Call SSOV
    bool public isPut;

    /// @dev Contract addresses
    Addresses public addresses;

    /// @dev Collateral Token
    IERC20 public collateralToken;

    /// @dev Current epoch for ssov
    uint256 public currentEpoch;

    /// @dev Expire delay tolerance
    uint256 public expireDelayTolerance = 5 minutes;

    /// @dev The precision of the collateral token
    uint256 public collateralPrecision;

    /// @dev Options token precision
    uint256 internal constant OPTIONS_PRECISION = 1e18;

    /// @dev Strikes, prices and collateral exchange rate is stored in the default precision which is 1e8
    uint256 internal constant DEFAULT_PRECISION = 1e8;

    /// @dev Reward distribution rate precision and any reward token precision
    uint256 internal constant REWARD_PRECISION = 1e18;

    /// @dev Checkpoints (epoch => strike => checkpoints[])
    mapping(uint256 => mapping(uint256 => VaultCheckpoint[]))
        public checkpoints;

    /// @dev epoch => EpochData
    mapping(uint256 => EpochData) internal epochData;

    /// @dev Mapping of (epoch => (strike => EpochStrikeData))
    mapping(uint256 => mapping(uint256 => EpochStrikeData))
        internal epochStrikeData;

    /// @dev tokenId => WritePosition
    mapping(uint256 => WritePosition) internal writePositions;

    /*==== ERRORS ====*/

    event ExpireDelayToleranceUpdate(uint256 expireDelayTolerance);

    event AddressesSet(Addresses addresses);

    event EmergencyWithdraw(address sender);

    event EpochExpired(address sender, uint256 settlementPrice);

    event Bootstrap(uint256 epoch, uint256[] strikes);

    event Deposit(uint256 tokenId, address indexed to, address indexed sender);

    event Purchase(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        uint256 premium,
        uint256 fee,
        address indexed to,
        address indexed sender
    );

    event Settle(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        uint256 pnl, // pnl transfered to the user
        uint256 fee, // fee sent to fee distributor
        address indexed to,
        address indexed sender
    );

    event Withdraw(
        uint256 tokenId,
        uint256 collateralTokenWithdrawn,
        uint256[] rewardTokenWithdrawAmounts,
        address indexed to,
        address indexed sender
    );
}

