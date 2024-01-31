// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ERC20.sol";
import "./AccessControl.sol";

contract RewardToken is ERC20, AccessControl, Ownable{
    event Bought(uint256 amount);

    address private withdrawAddress = address(0);

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // _mint(msg.sender, 100 * 10**uint(decimals()));
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public {
        // Check that the calling account has the minter role
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(hasRole(BURNER_ROLE, msg.sender), "Caller is not a burner");
        _burn(from, amount);
    }

    function grantMinter(address to) external onlyOwner {
        _grantRole(MINTER_ROLE, to);
    }

    function grantBurner(address to) external onlyOwner {
        _grantRole(BURNER_ROLE, to);
    }

    function buy() payable public {
        uint256 amountTobuy = msg.value;
        require(amountTobuy > 0, "You need to send some ether");
        _mint(msg.sender, amountTobuy);
        emit Bought(amountTobuy);
    }

    function setWithdrawAddress(address _withdrawAddress) external onlyOwner {
        withdrawAddress = _withdrawAddress;
    }

    function withdraw() external onlyOwner {
        require(withdrawAddress != address(0), "No withdraw address");
        payable(withdrawAddress).transfer(address(this).balance);
    }
}
