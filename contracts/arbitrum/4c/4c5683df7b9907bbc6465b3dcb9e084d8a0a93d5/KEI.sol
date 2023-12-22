
//  $$   /$$ /$$$$$$$$ /$$$$$$$
// | $$  /$$/| $$_____/|_  $$_/       KEI is a yield-bearing meta stablecoin by Keiko Finance
// | $$ /$$/ | $$        | $$       it agreggates and distributes yield from other stable tokens to   
// | $$$$$/  | $$$$$     | $$                               KEI Holders
// | $$  $$  | $$__/     | $$  
// | $$\  $$ | $$        | $$       Reserves are managed by KEIManager.sol and ReserveController.sol
// | $$ \  $$| $$$$$$$$ /$$$$$$                both controlled by on-chain governance
// |__/  \__/|________/|______/
                            
// https://www.github.com/KeikoFinance
// https://www.twitter.com/KeikoFinance                

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";

contract KEI is Owned, ERC20 {

    string private constant NAME = "KEI Stablecoin";
    string private constant SYMBOL = "KEI";
    uint8 private constant DECIMALS = 18;

    constructor(address initialOwner) Owned(initialOwner) ERC20(NAME, SYMBOL, DECIMALS) {}

    function mint(address account, uint256 amount) public onlyOwner() {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner() {
        _burn(account, amount);
    }

    function withdrawStuckKEIKO() external onlyOwner {
        uint256 balance = ERC20(address(this)).balanceOf(address(this));
        ERC20(address(this)).transfer(msg.sender, balance);
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawStuckToken(address _token, address _to) external onlyOwner {
        require(_token != address(0), "_token address cannot be 0");
        uint256 _contractBalance = ERC20(_token).balanceOf(address(this));
        ERC20(_token).transfer(_to, _contractBalance);
    }

    function withdrawStuckEth(address toAddr) external onlyOwner {
        (bool success, ) = toAddr.call{
            value: address(this).balance
        } ("");
        require(success);
    }
}
