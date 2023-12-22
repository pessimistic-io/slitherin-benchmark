// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./IArbToken.sol";

contract DGenesisVaultToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    IArbToken,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GATEWAY_ROLE = keccak256("GATEWAY_ROLE");
    bytes32 public constant ARBITRUMADMIN_ROLE =
        keccak256("ARBITRUMADMIN_ROLE");

    bool public arbEnabled;

    address public l2Gateway;
    address public mainnetAddress;

    function initialize() public initializer {
        __ERC20_init("dGenesis Vault Token", "DGV");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _mint(msg.sender, 4000 * 10**decimals());
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(GATEWAY_ROLE, msg.sender);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setArbState(bool _arbEnabled) public onlyRole(ARBITRUMADMIN_ROLE) {
        arbEnabled = _arbEnabled;
    }

    function setl2Gateway(address _l2Gateway)
        external
        onlyRole(ARBITRUMADMIN_ROLE)
    {
        require(arbEnabled, "Not Enabled");
        l2Gateway = _l2Gateway;
    }

    function setl1Address(address _mainnetAddress)
        external
        onlyRole(ARBITRUMADMIN_ROLE)
    {
        require(arbEnabled, "Not Enabled");
        mainnetAddress = _mainnetAddress;
    }

    function l1Address() external view override returns (address) {
        require(arbEnabled, "Not Enabled");
        return mainnetAddress;
    }

    function bridgeMint(address _account, uint256 _amount)
        external
        override
        onlyRole(GATEWAY_ROLE)
    {
        require(arbEnabled, "Not Enabled");
        _mint(_account, _amount);
    }

    function bridgeBurn(address _account, uint256 _amount)
        external
        override
        onlyRole(GATEWAY_ROLE)
    {
        require(arbEnabled, "Not Enabled");
        _burn(_account, _amount);
    }

    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(_from, _to, _amount);
    }
}

