// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.5;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./SafeMath.sol";

import "./IERC20.sol";
import "./IOHM.sol";
import "./IERC20Permit.sol";

import "./ERC20Permit.sol";

contract vUNIT is ERC20Permit, IOHM, Ownable, AccessControl {
    using SafeMath for uint256;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	address public childChainManagerProxy;

    constructor () 
        ERC20("Virtual Unit", "vUNIT", 18) 
        ERC20Permit("Virtual Unit") 
    {

    }

	function mint (address account, uint256 amount) public override {
		require(hasRole(MINTER_ROLE, msg.sender), "vUNIT: caller is not a minter");
		_mint(account, amount);
	}

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

	function burn (address account, uint256 amount)  external {
		require(hasRole(MINTER_ROLE, msg.sender), "vUNIT: caller is not a burner");
		_burn(account, amount);
	}

	// being proxified smart contract, most probably childChainManagerProxy contract's address
    // is not going to change ever, but still, lets keep it 
    function updateChildChainManager(address newChildChainManagerProxy) external onlyOwner {
        require(newChildChainManagerProxy != address(0), "Bad ChildChainManagerProxy address");
        
        childChainManagerProxy = newChildChainManagerProxy;
    }

    function deposit(address user, bytes calldata depositData) external {
        require(msg.sender == childChainManagerProxy, "You're not allowed to deposit");

        uint256 amount = abi.decode(depositData, (uint256));

        mint(user, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external override {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) internal {
        uint256 decreasedAllowance_ = allowance(account_, msg.sender).sub(amount_, "ERC20: burn amount exceeds allowance");

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function setMinter(address _minter) public onlyOwner {
        _setupRole(MINTER_ROLE, _minter);
    }
}
