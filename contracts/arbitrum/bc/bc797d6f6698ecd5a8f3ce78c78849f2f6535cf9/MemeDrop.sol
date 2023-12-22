// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

/*
 * $$\      $$\                                   $$$$$$$\                                
 * $$$\    $$$ |                                  $$  __$$\                               
 * $$$$\  $$$$ | $$$$$$\  $$$$$$\$$$$\   $$$$$$\  $$ |  $$ | $$$$$$\   $$$$$$\   $$$$$$\  
 * $$\$$\$$ $$ |$$  __$$\ $$  _$$  _$$\ $$  __$$\ $$ |  $$ |$$  __$$\ $$  __$$\ $$  __$$\ 
 * $$ \$$$  $$ |$$$$$$$$ |$$ / $$ / $$ |$$$$$$$$ |$$ |  $$ |$$ |  \__|$$ /  $$ |$$ /  $$ |
 * $$ |\$  /$$ |$$   ____|$$ | $$ | $$ |$$   ____|$$ |  $$ |$$ |      $$ |  $$ |$$ |  $$ |
 * $$ | \_/ $$ |\$$$$$$$\ $$ | $$ | $$ |\$$$$$$$\ $$$$$$$  |$$ |      \$$$$$$  |$$$$$$$  |
 * \__|     \__| \_______|\__| \__| \__| \_______|\_______/ \__|       \______/ $$  ____/ 
 *                                                                              $$ |      
 *                                                                              $$ |      
 *                                                                              \__|      
 */

import "./ERC20.sol";
import "./IERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract MemeDrop is ERC20, ERC20Burnable, Ownable {
    uint256 public claimFee = 300000000000000; // .0003 ETH
    uint256 public claimAmount = 1000000000 * 10**18; // 1 Billion MEMD
    uint256 private _maxCap = 500000000000000 * 10**18; // 500 Trillion MEMD

    bool public airdropIsActive = false;

    mapping(address => bool) public blacklisted;
    mapping(address => bool) public tokensClaimed;

    constructor() ERC20('MemeDrop', 'MEMD') {
        _mint(msg.sender, _maxCap);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!blacklisted[from] && !blacklisted[to], "Transfer blacklisted");
        super._beforeTokenTransfer(from, to, amount);
    }

    function setAirdropState() external onlyOwner {
        airdropIsActive = !airdropIsActive;
    }

    function claimAirdrop() external payable {
        require(airdropIsActive, "Airdrop must be active to claim tokens");
        require(tokensClaimed[msg.sender] == false, "You already claimed the airdrop");

        IERC20 memd = IERC20(address(this));

        require(memd.balanceOf(address(this)) > 0, "Token balance is zero");
        require(claimFee == msg.value, "Missing claim fee.");

        memd.transfer(msg.sender, claimAmount);
        tokensClaimed[msg.sender] = true;
    }

    function blacklist(address _user, bool _isBlacklisted) external onlyOwner {
        blacklisted[_user] = _isBlacklisted;
    }

    function withdrawToken(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);

        uint256 _amount = token.balanceOf(address(this));

        if(_token != address(this)) {
            token.approve(address(this), _amount);
            token.transferFrom(address(this), owner(), _amount);
        } else {
            token.transfer(msg.sender, _amount);
        }        
    }

    function withdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;

        payable(msg.sender).transfer(balance);
    }
}
