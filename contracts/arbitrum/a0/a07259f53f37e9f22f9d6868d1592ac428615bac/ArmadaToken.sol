// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20Upgradeable.sol";

contract ArmadaToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    address public vestingContract;
    mapping(address => bool) public whitelistedSender;

    modifier onlyVestingAndOwner() {
        require(msg.sender == vestingContract || msg.sender == owner(), "NOT_ADMIN");
        _;
    }

    function initialize() public initializer {
        __ERC20_init("Cruize escrowed token", "ARMADA");
        __Ownable_init();
        whitelistedSender[msg.sender] = true;
    }

    function name() public view virtual override returns (string memory) {
        return "Escrowed Cruize";
    }

    function symbol() public view virtual override returns (string memory) {
        return "esCRUIZE";
    }

    function mint(address to, uint256 amount) public onlyVestingAndOwner {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyVestingAndOwner {
        _burn(to, amount);
    }

    function setVestingAddress(address _vestingContract) public onlyOwner {
        require(_vestingContract != address(0));
        vestingContract = _vestingContract;
    }

    function toggleWhitelist(address _account) public onlyOwner {
        require(_account != address(0));
        whitelistedSender[_account] = !whitelistedSender[_account];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        /// @note only permitted accounts can transfer token
        require(
            whitelistedSender[from] || from == address(0) || to == address(0),
            "NOT-TRANSFERRABLE"
        );
        super._beforeTokenTransfer(from, to, amount);
    }
}

