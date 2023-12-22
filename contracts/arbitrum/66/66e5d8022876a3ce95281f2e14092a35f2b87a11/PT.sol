// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./MinterPauserClaimableERC20.sol";
import "./IFutureVault.sol";
import "./IPT.sol";
import "./ClaimableERC20.sol";

/**
 * @title APWine interest bearing token
 * @notice Interest bearing token for the futures liquidity provided
 * @dev the value of an APWine IBT is equivalent to a fixed amount of underlying tokens of the futureVault IBT
 */
contract PT is IPT, MinterPauserClaimableERC20 {
    using SafeMathUpgradeable for uint256;

    IFutureVault public override futureVault;

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * futureVault
     *
     * See {ERC20-constructor}.s
     */

    function initialize(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address futureAddress
    ) public initializer {
        super.initialize(name, symbol);
        _setupRole(DEFAULT_ADMIN_ROLE, futureAddress);
        _setupRole(MINTER_ROLE, futureAddress);
        _setupRole(PAUSER_ROLE, futureAddress);
        futureVault = IFutureVault(futureAddress);
        _setupDecimals(decimals);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        // sender and receiver state update
        if (
            from != address(futureVault) &&
            to != address(futureVault) &&
            from != address(0x0) &&
            to != address(0x0)
        ) {
            futureVault.updateUserState(from);
            futureVault.updateUserState(to);
            require(
                balanceOf(from) >=
                    amount.add(futureVault.getTotalDelegated(from)),
                "ERC20: transfer amount exceeds transferrable balance"
            );
        }
    }

    function getFutureAddress() internal override returns (address) {
        return address(futureVault);
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount)
        public
        override(IPT, MinterPauserClaimableERC20)
    {
        super.mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual override(IPT, ClaimableERC20) {
        super.burn(amount);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public override(IPT, MinterPauserClaimableERC20) {
        super.pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public override(IPT, MinterPauserClaimableERC20) {
        super.unpause();
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount)
        public
        override(IPT, ClaimableERC20)
    {
        if (msg.sender != address(futureVault)) {
            super.burnFrom(account, amount);
        } else {
            _burn(account, amount);
        }
    }

    /**
     * @notice Returns the current balance of one user including the pt that were not claimed yet
     * @param account the address of the account to check the balance of
     * @return the total pt balance of one address
     */
    function balanceOf(address account)
        public
        view
        override(IPT, ClaimableERC20)
        returns (uint256)
    {
        return
            super.balanceOf(account).add(
                futureVault.getClaimablePT(
                    account,
                    futureVault.getTotalDelegated(account)
                )
            );
    }

    /**
     * @notice Returns the current balance of one user (without the claimable amount)
     * @param account the address of the account to check the balance of
     * @return the current pt balance of this address
     */
    function recordedBalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return super.balanceOf(account);
    }

    uint256[50] private __gap;
}

