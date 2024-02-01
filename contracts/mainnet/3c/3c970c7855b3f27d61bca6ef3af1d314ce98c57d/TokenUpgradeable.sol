// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20Upgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./PausableUpgradeable.sol";

contract TokenUpgradeable is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable {

    address public admin;
    mapping(address => uint256) public lockedTokens;
    uint8 private _decimals;

    /**
     * @dev Throws if called by any account other than the master.
     */
    modifier onlyAdmin() {
        require(admin == _msgSender(), "NOT_ADMIN");
        _;
    }

    function initialize(
        string calldata _name, 
        string calldata _ticker, 
        uint8 _decimal, 
        address _admin
    ) public initializer {
        require(_admin != address(0), "INVALID_ADMIN");
        __ERC20_init(_name, _ticker);
        __Ownable_init();
        __Pausable_init();
        admin = _admin;
        _decimals = _decimal;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mintTokens(address to, uint256 amount) public onlyOwner whenNotPaused {
        _mint(to, amount);
    }

    function burnTokens(address from, uint256 amount) public onlyOwner whenNotPaused {
        _burn(from, amount);
    }

    function renounceOwnership() public override onlyAdmin {
        _transferOwnership(admin);
    }

    function transferAdminOwnership(address _newAdmin) public onlyAdmin {
        require(_newAdmin != address(0), "INVALID_ADMIN");
        admin = _newAdmin;
    }
    
    function pauseTokens() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpauseTokens() public onlyOwner whenPaused {
        _unpause();
    }

    /**
    * @notice lock the token of any token holder.
    * @dev balance should be greater than amount. function will revert will balance is less than amount.
    * @param holder the addrress of token holder.
    * @param amount number of tokens to burn.
    * @return true when lockToken succeeded.
    */

    function lockTokens(address holder, uint256 amount) external onlyOwner whenNotPaused returns (bool) {
        require(balanceOf(holder) >= amount, "INSUFFICIENT_BALANCE");

        // _balances[holder] = _balances[holder].sub(amount);
        burnTokens(holder, amount);
        lockedTokens[holder] += amount;

        return true;
    }

    /**
    * @notice unLock the token of any token holder.
    * @dev locked balance should be greater than amount. function will revert will locked balance is less than amount.
    * @param holder the addrress of token holder.
    * @param amount number of tokens to burn.
    * @return true when unLockToken succeeded.
    */

    function unlockToken(address holder, uint256 amount) external onlyOwner whenNotPaused returns (bool) {
        require(lockedTokens[holder] >= amount, "INSUFFICIENT_LOCKED_TOKENS");

        lockedTokens[holder] -= amount;
        mintTokens(holder, amount);

        return true;
    }
}

