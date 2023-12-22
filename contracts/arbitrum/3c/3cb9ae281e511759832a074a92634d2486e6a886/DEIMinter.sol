// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.17;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IDEI.sol";

/// @title DEI Minter
/// @author DEUS Finance◘
contract DEIMinter is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Mint(address user, uint256 deiAmount, uint256 collatAmount);

    event SetFees(uint256 oldMintingFee, uint256 newMintingFee);

    event EmergencyWithdraw(
        address token,
        address sender,
        address to,
        uint256 amount
    );

    string public constant VERSION = "1.0.0";

    address public dei;
    address public collateral;

    uint256 public mintingFee; // scale 1e6
    uint256 public mintingLimit;
    uint256 public mintedDeiAmount;

    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant EMERGENCY_WITHDRAW_ROLE =
        keccak256("EMERGENCY_WITHDRAW_ROLE");

    uint256 private constant SCALE = 1e6;

    function initialize(
        address admin,
        address deiAddress,
        address collateralAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();

        dei = deiAddress;
        collateral = collateralAddress;
        mintingFee = 1000;
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(PAUSER_ROLE, admin);
        _setupRole(SETTER_ROLE, admin);
    }

    function setMintLimit(uint256 amount) external onlyRole(SETTER_ROLE) {
        mintingLimit = amount;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function mint(uint256 collatAmount) public whenNotPaused {
        uint256 deiAmount = collatAmount * 1e12;
        deiAmount -= (deiAmount * mintingFee) / SCALE;
        require(
            deiAmount + mintedDeiAmount <= mintingLimit,
            "Mint Limit reached"
        );
        mintedDeiAmount += deiAmount;
        IERC20Upgradeable(collateral).safeTransferFrom(
            msg.sender,
            address(this),
            collatAmount
        );

        IDEI(dei).mint(msg.sender, deiAmount);
        emit Mint(msg.sender, deiAmount, collatAmount);
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(EMERGENCY_WITHDRAW_ROLE) {
        IERC20Upgradeable(token).safeTransfer(to, amount);

        emit EmergencyWithdraw(token, msg.sender, to, amount);
    }

    function setFees(uint256 mintingFee_) external onlyRole(SETTER_ROLE) {
        emit SetFees(mintingFee, mintingFee_);
        mintingFee = mintingFee_;
    }
}

