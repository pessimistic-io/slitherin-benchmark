// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";

import "./ISyntheX.sol";
import "./Errors.sol";

/**
 * @title SyntheX Token contract
 * @author Prasad prasad@chainscore.finance
 * @notice SyntheX Token contract, based on OpenZeppelin ERC20
 * @dev Pausable, Burnable, Permit
 */
contract SyntheXToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    /// @notice System contract to check access control
    ISyntheX public synthex;

    /// @notice gap for future storage variables
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _synthex) public initializer {
        __ERC20_init("SyntheX Token", "SYX");
        __ERC20Burnable_init();
        __ERC20Permit_init("SyntheX Token");
        __Pausable_init();
        __UUPSUpgradeable_init();

        // validate synthex address
        require(ISyntheX(_synthex).supportsInterface(type(ISyntheX).interfaceId), Errors.INVALID_ADDRESS);
        // set synthex
        synthex = ISyntheX(_synthex);
    }

    ///@notice required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyL1Admin {}

    modifier onlyL1Admin() {
        require(synthex.isL1Admin(msg.sender), Errors.CALLER_NOT_L1_ADMIN);
        _;
    }

    modifier onlyL2Admin() {
        require(synthex.isL2Admin(msg.sender), Errors.CALLER_NOT_L2_ADMIN);
        _;
    }

    // support interface
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC20Upgradeable).interfaceId || interfaceId == type(IERC20MetadataUpgradeable).interfaceId;
    }

    /**
     * @notice Pause the token transfers, mints and burns
     * @dev Only L2_ADMIN can pause
     */
    function pause() external onlyL2Admin {
        _pause();
    }

    /**
     * @notice Unpause the token transfers, mints and burns
     * @dev Only L2_ADMIN can unpause
     */
    function unpause() external onlyL2Admin {
        _unpause();
    }

    /**
     * @notice Mint tokens
     * @dev Only L1_ADMIN can mint
     * @param to Address to mint tokens to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public onlyL1Admin {
        _mint(to, amount);
    }

    /**
     * @dev Override _beforeTokenTransfer hook to add pausable functionality
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
