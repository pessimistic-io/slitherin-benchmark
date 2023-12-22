pragma solidity ^0.4.26;

import "./Ownable.sol";
import "./IERC20.sol";

/**
 * @dev Main functions:
 */
contract SecurityBaseFor4 is Ownable {

    event EmergencyWithdraw(address token, address to, uint256 amount);
    event SetWhitelist(address account, bool knob);

    // whitelist
    mapping(address => bool) public whitelist;

    constructor() {}

    modifier onlyWhitelist() {
        require(whitelist[msg.sender], "SecurityBase::onlyWhitelist: isn't in the whitelist");
        _;
    }

    function setWhitelist(address account, bool knob) external onlyOwner {
        whitelist[account] = knob;
        emit SetWhitelist(account, knob);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token != address(0)) {
            IERC20(token).transfer(to, amount);
        } else {
            to.transfer(amount);
        }
        emit EmergencyWithdraw(token, to, amount);
    }
}
