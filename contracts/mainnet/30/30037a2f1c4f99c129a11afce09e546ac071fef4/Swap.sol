// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";

contract Swap is Ownable, Pausable {
    using SafeERC20 for IERC20;

    address public ccToken;
    mapping(address => bool) public tokens;
    
    event Swapped(address indexed account, address indexed token, uint256 amount);
    event Withdrawn(address indexed account, address indexed token, uint256 amount);

    constructor(address addr_) {
        ccToken = addr_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function addToken(address addr_) external onlyOwner {
        require(addr_ != address(0), "addr_ cannot be an zero address");
        tokens[addr_] = true;
    }

    function removeToken(address addr_) external onlyOwner {
        require(addr_ != address(0), "addr_ cannot be an zero address");
        tokens[addr_] = false;
    }

    function swapCC(address addr_, uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");
        require(tokens[addr_] == true, "ERC20 tokens are not supported");

        IERC20(addr_).safeTransferFrom(_msgSender(), address(this), amount * (10 ** (IERC20Metadata(addr_).decimals() - 4)));
        IERC20(ccToken).safeTransfer(_msgSender(), amount * (10 ** (IERC20Metadata(ccToken).decimals() - 4)));
        emit Swapped(_msgSender(), addr_, amount);
    }

    function withdraw(address token, address account, uint256 amount) external onlyOwner{
        require(token != address(0), "token cannot be an zero address");
        require(account != address(0), "account cannot be an zero address");
        IERC20(token).safeTransfer(account, amount);
        emit Withdrawn(account, token, amount);
    }
}
