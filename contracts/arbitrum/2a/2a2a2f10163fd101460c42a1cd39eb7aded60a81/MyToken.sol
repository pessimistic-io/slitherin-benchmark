// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./ERC20PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract AiHQianLan is Initializable, ERC20Upgradeable, ERC20PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    address private constant BUG_BOUNTY_PROGRAM_ADDRESS = 0x2bd34aD6001203602EB9a02De559181E9fA7EFBe;
    address private constant TEAM_ADDRESS = 0x903BbfFc49463B20e6082DAe16d948A8ef67E280;
    address private constant FOUNDATION_ADDRESS = 0xB7037f4B4f582dc50a64472A509DCf2bb89f02e2;

    uint256 private constant TOTAL_SUPPLY = 10000000000 * 10**18;
    uint256 private constant BUG_BOUNTY_SUPPLY = 880000000 * 10**18;
    uint256 private constant TEAM_SUPPLY = 810000000 * 10**18;
    uint256 private constant FOUNDATION_SUPPLY = 1810000000 * 10**18;

    uint256 private constant LOCK_DURATION = 88 days;

    uint256 private releaseTime;

    mapping(address => bool) private _isFrozen;

    event TokensFrozen(address indexed target, bool frozen);

    modifier onlyUnfrozen(address target) {
        require(!_isFrozen[target], "AiHQianLan: account is frozen");
        _;
    }

    function initialize() public initializer {
        __ERC20_init("AiHQianLan", "HQL");
        __ERC20Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        _mint(_msgSender(), TOTAL_SUPPLY - BUG_BOUNTY_SUPPLY - TEAM_SUPPLY - FOUNDATION_SUPPLY);
        _mint(BUG_BOUNTY_PROGRAM_ADDRESS, BUG_BOUNTY_SUPPLY);
        _mint(TEAM_ADDRESS, TEAM_SUPPLY);
        _mint(FOUNDATION_ADDRESS, FOUNDATION_SUPPLY);

        _isFrozen[BUG_BOUNTY_PROGRAM_ADDRESS] = true;
        _isFrozen[TEAM_ADDRESS] = true;
        _isFrozen[FOUNDATION_ADDRESS] = true;

        emit TokensFrozen(BUG_BOUNTY_PROGRAM_ADDRESS, true);
        emit TokensFrozen(TEAM_ADDRESS, true);
        emit TokensFrozen(FOUNDATION_ADDRESS, true);

        releaseTime = block.timestamp + LOCK_DURATION;

// Set the contract owner address to 0x8F145aa77c707Ba657A8F7f958c010880F7Ff1f2 during deployment
        transferOwnership(0x8F145aa77c707Ba657A8F7f958c010880F7Ff1f2);
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        onlyUnfrozen(_msgSender())
        onlyUnfrozen(recipient)
        returns (bool)
    {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override onlyUnfrozen(sender) onlyUnfrozen(recipient) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        onlyUnfrozen(_msgSender())
        onlyUnfrozen(spender)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    function freezeAccount(address target, bool freeze) external onlyOwner {
        _isFrozen[target] = freeze;
        emit TokensFrozen(target, freeze);
    }

    function isFrozen(address target) external view returns (bool) {
        return _isFrozen[target];
    }

    function unlockTokens() external {
        require(block.timestamp >= releaseTime, "AiHQianLan: tokens are locked");
        require(_isFrozen[_msgSender()], "AiHQianLan: account is not locked");

        _isFrozen[_msgSender()] = false;
        emit TokensFrozen(_msgSender(), false);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
