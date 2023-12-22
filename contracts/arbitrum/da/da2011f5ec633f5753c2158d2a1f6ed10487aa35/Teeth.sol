// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Snapshot.sol";
import "./AccessControl.sol";
import "./Pausable.sol";

contract Teeth is ERC20, ERC20Burnable, ERC20Snapshot, AccessControl, Pausable {
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private immutable _cap;
    uint256 private _totalMintedSupply;

    constructor(uint256 cap_) ERC20("Teeth", "TEETH") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(SNAPSHOT_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());


        _cap = cap_;
    }

    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function totalMintedSupply() public view virtual returns (uint256) {
        return _totalMintedSupply;
    }

    function totalBurnedSupply() public view virtual returns (uint256) {
        return _totalMintedSupply - totalSupply();
    }


    function snapshot() public onlyRole(SNAPSHOT_ROLE) {
        _snapshot();
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function grantMinter(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MINTER_ROLE, account);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual override {
        require(totalMintedSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        super._mint(account, amount);
        _totalMintedSupply += amount;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        // Minting is allowed even while paused
        if (from != address(0)) {
            require(!paused(), "Pausable: paused");
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
