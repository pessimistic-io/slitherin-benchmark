// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract Migrator is
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum MigrationPreference {
        BALANCED, // 0
        DEUS, // 1
        SYMM // 2
    }

    struct Migration {
        address user;
        address token;
        uint256 amount;
        uint256 timestamp;
        uint256 block;
        MigrationPreference migrationPreference;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    uint256 public earlyMigrationDeadline;

    // total migrated amount by token address by project
    mapping(MigrationPreference => mapping(address => uint256))
        public totalLateMigratedAmount;

    mapping(MigrationPreference => mapping(address => uint256))
        public totalEarlyMigratedAmount;

    // user migrated amount: project => user => token => amount
    mapping(MigrationPreference => mapping(address => mapping(address => uint256)))
        public migratedAmount;

    // list of user migrations
    mapping(address => Migration[]) public migrations;

    event Migrate(
        address[] token,
        uint256[] amount,
        MigrationPreference[] migrationPreference,
        address receiver
    );

    function initialize(address _admin) external initializer {
        __Pausable_init();
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        earlyMigrationDeadline = block.timestamp + 30 days;
    }

    function pause() external onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function deposit(
        address[] memory tokens,
        uint256[] memory amounts,
        MigrationPreference[] memory migrationPreferences,
        address receiver
    ) external whenNotPaused {
        for (uint256 i; i < tokens.length; ++i) {
            IERC20Upgradeable(tokens[i]).safeTransferFrom(
                msg.sender,
                address(this),
                amounts[i]
            );

            if (block.timestamp < earlyMigrationDeadline) {
                totalEarlyMigratedAmount[migrationPreferences[i]][
                    tokens[i]
                ] += amounts[i];
            } else {
                totalLateMigratedAmount[migrationPreferences[i]][
                    tokens[i]
                ] += amounts[i];
            }

            migratedAmount[migrationPreferences[i]][receiver][
                tokens[i]
            ] += amounts[i];

            migrations[receiver].push(
                Migration({
                    user: receiver,
                    token: tokens[i],
                    amount: amounts[i],
                    timestamp: block.timestamp,
                    block: block.number,
                    migrationPreference: migrationPreferences[i]
                })
            );
        }

        emit Migrate(tokens, amounts, migrationPreferences, receiver);
    }

    function getUserMigrations(
        address user
    ) external view returns (Migration[] memory userMigrations) {
        userMigrations = new Migration[](migrations[user].length);
        for (uint256 i; i < userMigrations.length; ++i) {
            userMigrations[i] = migrations[user][i];
        }
    }

    function getTotalEarlyMigratedAmounts(
        address[] memory tokens
    )
        external
        view
        returns (
            uint256[] memory balancedAmounts,
            uint256[] memory deusAmounts,
            uint256[] memory symmAmounts
        )
    {
        balancedAmounts = new uint256[](tokens.length);
        deusAmounts = new uint256[](tokens.length);
        symmAmounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            balancedAmounts[i] = totalEarlyMigratedAmount[
                MigrationPreference.BALANCED
            ][tokens[i]];
            deusAmounts[i] = totalEarlyMigratedAmount[MigrationPreference.DEUS][
                tokens[i]
            ];
            symmAmounts[i] = totalEarlyMigratedAmount[MigrationPreference.SYMM][
                tokens[i]
            ];
        }
    }

    function getTotalLateMigratedAmounts(
        address[] memory tokens
    )
        external
        view
        returns (
            uint256[] memory balancedAmounts,
            uint256[] memory deusAmounts,
            uint256[] memory symmAmounts
        )
    {
        balancedAmounts = new uint256[](tokens.length);
        deusAmounts = new uint256[](tokens.length);
        symmAmounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            balancedAmounts[i] = totalLateMigratedAmount[
                MigrationPreference.BALANCED
            ][tokens[i]];
            deusAmounts[i] = totalLateMigratedAmount[MigrationPreference.DEUS][
                tokens[i]
            ];
            symmAmounts[i] = totalLateMigratedAmount[MigrationPreference.SYMM][
                tokens[i]
            ];
        }
    }

    function withdraw(
        address[] memory tokens
    ) external onlyRole(WITHDRAWER_ROLE) {
        for (uint256 i; i < tokens.length; ++i) {
            IERC20Upgradeable(tokens[i]).safeTransfer(
                msg.sender,
                IERC20Upgradeable(tokens[i]).balanceOf(address(this))
            );
        }
    }

    function setEarlyMigrationDeadline(
        uint256 _deadline
    ) external onlyRole(SETTER_ROLE) {
        earlyMigrationDeadline = _deadline;
    }
}

