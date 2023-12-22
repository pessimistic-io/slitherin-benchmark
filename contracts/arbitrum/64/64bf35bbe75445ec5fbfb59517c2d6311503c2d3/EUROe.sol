// SPDX-License-Identifier: MIT

/*
Copyright (c) 2023 Membrane Finance Oy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

pragma solidity 0.8.4;

import "./ERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

/**
@title A stablecoin ERC20 token contract for EUROe
@author Membrane Finance
@notice This contract implements the EUROe stablecoin along with its core functionality, such as minting and burning
@dev This contract is upgradable. It is implemented as an EIP-1967 transparent upgradable proxy. The PROXYOWNER_ROLE controls upgrades to this contract. The DEFAULT_ADMIN_ROLE grants and revokes roles.
 */
contract EUROe is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant PROXYOWNER_ROLE = keccak256("PROXYOWNER_ROLE");
    bytes32 public constant BLOCKLISTER_ROLE = keccak256("BLOCKLISTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BLOCKED_ROLE = keccak256("BLOCKED_ROLE");
    bytes32 public constant RESCUER_ROLE = keccak256("RESCUER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /**
     * @dev Emitted once a minting set has been completed
     * @param id External identifier for the minting set
     */
    event MintingSetCompleted(uint256 indexed id);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the (upgradeable) contract.
     * @param proxyOwner Address for whom to give the proxyOwner role
     * @param admin Address for whom to give the admin role
     * @param blocklister Address for whom to give the blocklister role
     * @param pauser Address for whom to give the pauser role
     * @param unpauser Address for whom to give the unpauser role
     * @param minter Address for whom to give the minter role
     */
    function initialize(
        address proxyOwner,
        address admin,
        address blocklister,
        address pauser,
        address unpauser,
        address minter,
        address rescuer,
        address burner
    ) external initializer {
        __ERC20_init("EUROe Stablecoin", "EUROe");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("EUROe Stablecoin");
        __UUPSUpgradeable_init();

        _grantRole(PROXYOWNER_ROLE, proxyOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BLOCKLISTER_ROLE, blocklister);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UNPAUSER_ROLE, unpauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(RESCUER_ROLE, rescuer);
        _grantRole(BURNER_ROLE, burner);

        // Add this contract as blocked so it can't receive its own tokens by accident
        _grantRole(BLOCKED_ROLE, address(this));

        _setRoleAdmin(BLOCKED_ROLE, BLOCKLISTER_ROLE);
    }

    /// @inheritdoc ERC20Upgradeable
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc ERC20BurnableUpgradeable
    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    /// @inheritdoc ERC20BurnableUpgradeable
    function burnFrom(address account, uint256 amount)
        public
        override
        onlyRole(BURNER_ROLE)
    {
        super.burnFrom(account, amount);
    }

    /**
     * @dev Consumes a received permit and burns tokens based on the permit
     * @param owner Source of the permit and allowance
     * @param spender Target of the permit and allowance
     * @param value How many tokens were permitted to be burned
     * @param deadline Until what timestamp the permit is valid
     * @param v The v portion of the permit signature
     * @param r The r portion of the permit signature
     * @param s The s portion of the permit signature
     */
    function burnFromWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public onlyRole(BURNER_ROLE) {
        require(msg.sender == spender, "Invalid spender");
        super.permit(owner, spender, value, deadline, v, r, s);
        super.burnFrom(owner, value);
    }

    /**
     * @dev Mints tokens to the given account
     * @param account The account to mint tokens to
     * @param amount How many tokens to mint
     */
    function mint(address account, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
    {
        _mint(account, amount);
    }

    /**
     * @dev Performs a batch of mints
     * @param targets Array of addresses for which to mint
     * @param amounts Array of amounts to mint for the corresponding addresses
     * @param id An external identifier given for the minting set
     * @param checksum A checksum to make sure none of the input data has changed
     */
    function mintSet(
        address[] calldata targets,
        uint256[] calldata amounts,
        uint256 id,
        bytes32 checksum
    ) external onlyRole(MINTER_ROLE) {
        require(targets.length == amounts.length, "Unmatching mint lengths");
        require(targets.length > 0, "Nothing to mint");

        bytes32 calculated = keccak256(abi.encode(targets, amounts, id));
        require(calculated == checksum, "Checksum mismatch");

        for (uint256 i = 0; i < targets.length; i++) {
            require(amounts[i] > 0, "Mint amount not greater than 0");
            _mint(targets[i], amounts[i]);
        }
        emit MintingSetCompleted(id);
    }

    /**
     * @dev Modifier that checks that an account is not blocked. Reverts
     * if the account is blocked
     */
    modifier whenNotBlocked(address account) {
        require(!hasRole(BLOCKED_ROLE, account), "Blocked user");
        _;
    }

    /**
     * @dev Checks that the contract is not paused and that neither sender nor receiver are blocked before transferring tokens. See {ERC20Upgradeable-_beforeTokenTransfer}.
     * @param from source of the transfer
     * @param to target of the transfer
     * @param amount amount of tokens to be transferred
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused whenNotBlocked(from) whenNotBlocked(to) {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Restricts who can upgrade the contract. Executed when anyone tries to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(PROXYOWNER_ROLE)
    {}

    /**
     * @dev Returns the address of the implementation behind the proxy
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @notice Used for rescuing tokens sent to the contract. Contact EUROe if you have accidentally sent tokens to the contract.
     * @dev Allows the rescue of an arbitrary token sent accidentally to the contract
     * @param token Which token we want to rescue
     * @param to Where should the rescued tokens be sent to
     * @param amount How many should be rescued
     */
    function rescueERC20(
        IERC20Upgradeable token,
        address to,
        uint256 amount
    ) external onlyRole(RESCUER_ROLE) {
        token.safeTransfer(to, amount);
    }

    /**
     * @dev Prevent anyone from removing their own role (override OZ function)
     */
    function renounceRole(bytes32, address) public pure override {
        revert("Not supported");
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

