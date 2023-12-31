// SPDX-License-Identifier: GPL-2.0-or-later
// (C) Florence Finance, 2022 - https://florence.finance/
pragma solidity 0.8.17;

import "./SafeERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./FlorinToken.sol";
import "./Util.sol";

contract FlorinTreasury is AccessControlUpgradeable, PausableUpgradeable {
    bytes32 private constant LOAN_VAULT_ROLE = keccak256("LOAN_VAULT_ROLE");

    event Mint(address sender, address receiver, uint256 florinTokens);
    event Redeem(address redeemer, uint256 florinTokens, uint256 eurTokens);
    event DepositEUR(address from, uint256 eurTokens);

    FlorinToken public florinToken;

    IERC20Upgradeable public eurToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {} // solhint-disable-line

    function initialize(FlorinToken florinToken_, IERC20Upgradeable eurToken_) external initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        florinToken = florinToken_;
        eurToken = eurToken_;

        _pause();
    }

    /// @dev Pauses the Florin Treasury (only by DEFAULT_ADMIN_ROLE)
    function pause() external {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _pause();
    }

    /// @dev Unpauses the Florin Treasury (only by DEFAULT_ADMIN_ROLE)
    function unpause() external {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _unpause();
    }

    function setEurToken(IERC20Upgradeable eurToken_) external {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());

        if (address(eurToken_) != address(0)) {
            eurToken = eurToken_;
        }
    }

    function setFlorinToken(FlorinToken florinToken_) external {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());

        if (address(florinToken_) != address(0)) {
            florinToken = florinToken_;
        }
    }

    /// @dev Mint Florin Token to receiver address (only by LOAN_VAULT_ROLE && when not paused)
    /// @param receiver receiver address
    /// @param florinTokens amount of Florin Token to be minted
    function mint(address receiver, uint256 florinTokens) external whenNotPaused {
        _checkRole(LOAN_VAULT_ROLE, _msgSender());
        florinToken.mint(receiver, florinTokens);
        emit Mint(_msgSender(), receiver, florinTokens);
    }

    /// @dev Redeem (burn) Florin Token to Florin Treasury and receive eurToken (only when not paused)
    /// @param florinTokens amount of Florin Token to be burned
    function redeem(uint256 florinTokens) external whenNotPaused {
        florinToken.burnFrom(_msgSender(), florinTokens);
        uint256 eurTokens = Util.convertDecimalsERC20(florinTokens, florinToken, eurToken);
        SafeERC20Upgradeable.safeTransfer(eurToken, _msgSender(), eurTokens);
        emit Redeem(_msgSender(), florinTokens, eurTokens);
    }

    /// @dev Deposit eurToken to Florin Treasury
    /// @param eurTokens amount of eurToken to be deposited [18 decimals]
    function depositEUR(uint256 eurTokens) external whenNotPaused {
        eurTokens = Util.convertDecimals(eurTokens, 18, Util.getERC20Decimals(eurToken));

        if (eurTokens == 0) {
            revert Errors.TransferAmountMustBeGreaterThanZero();
        }

        SafeERC20Upgradeable.safeTransferFrom(eurToken, _msgSender(), address(this), eurTokens);
        emit DepositEUR(_msgSender(), eurTokens);
    }

    /// @dev Transfer the ownership of the Deposit eurToken to Florin Treasury (requires a previous approval by 'from')
    /// @param newOwner address of the new owner of the Florin Token
    function transferFlorinTokenOwnership(address newOwner) external {
        _checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
        florinToken.transferOwnership(newOwner);
    }
}

