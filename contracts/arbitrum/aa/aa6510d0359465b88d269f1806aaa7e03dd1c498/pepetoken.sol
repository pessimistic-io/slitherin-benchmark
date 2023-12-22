//SPDX-License-Identifier: MIT

//⠄⠄⠄⠄⣠⣴⣿⣿⣿⣷⣦⡠⣴⣶⣶⣶⣦⡀⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄
//⠄⠄⠄⣴⣿⣿⣫⣭⣭⣭⣭⣥⢹⣟⣛⣛⣛⣃⣀⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄
//⠄⣠⢸⣿⣿⣿⣿⢯⡓⢻⠿⠿⠷⡜⣯⠭⢽⠿⠯⠽⣀⠄⠄⠄⠄⠄⠄⠄⠄⠄
//⣼⣿⣾⣿⣿⣿⣥⣝⠂⠐⠈⢸⠿⢆⠱⠯⠄⠈⠸⣛⡒⠄⠄⠄⠄⠄⠄⠄⠄⠄
//⣿⣿⣿⣿⣿⣿⣿⣶⣶⣭⡭⢟⣲⣶⡿⠿⠿⠿⠿⠋⠄⠄⣴⠶⠶⠶⠶⠶⢶⡀
//⣿⣿⣿⣿⣿⢟⣛⠿⢿⣷⣾⣿⣿⣿⣿⣿⣿⣿⣷⡄⠄⢰⠇⠄⠄⠄⠄⠄⠈⣧
//⣿⣿⣿⣿⣷⡹⣭⣛⠳⠶⠬⠭⢭⣝⣛⣛⣛⣫⣭⡥⠄⠸⡄⣶⣶⣾⣿⣿⢇⡟
//⠿⣿⣿⣿⣿⣿⣦⣭⣛⣛⡛⠳⠶⠶⠶⣶⣶⣶⠶⠄⠄⠄⠙⠮⣽⣛⣫⡵⠊⠁
//⣍⡲⠮⣍⣙⣛⣛⡻⠿⠿⠿⠿⠿⠿⠿⠖⠂⠄⠄⠄⠄⠄⠄⠄⠄⣸⠄⠄⠄⠄
//⣿⣿⣿⣶⣦⣬⣭⣭⣭⣝⣭⣭⣭⣴⣷⣦⡀⠄⠄⠄⠄⠄⠄⠠⠤⠿⠦⠤⠄⠄

pragma solidity ^0.8.16;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";


contract pepetoken is
    ERC20,
    ERC20Burnable,
    Pausable,
    Ownable
    {
    uint256 public maxSupply;
    uint256 public price;


    //the beacon contract is initialized with the name, symbol, max supply and addresses with roles
    //when deploying proxies, provide the above values as constructor arguments
    //set max supply to 0 if there is no max supply
    //set transfer tax to 0 if there is no transfer tax
    //set tax receiver to 0x0 if there is no tax receiver

    constructor() ERC20("PEPE", "PEPE") {
        maxSupply = 690420000000 * 10**decimals();
        price = 0.00000001 ether;
        _pause();
    }


    function mint(address to, uint256 amount)
        public
        onlyOwner
    {
        require(totalSupply() + amount*10**decimals() <= maxSupply, "Max supply reached");
        _mint(to, amount*10**decimals());
    }

    function airdrop(address[] memory recipients, uint256[] memory amounts)
        public
        onlyOwner
    {
        require(
            recipients.length == amounts.length,
            "recipients and amounts must be of same length"
        );
        for (uint256 i = 0; i < recipients.length; i++) {
            mint(recipients[i], amounts[i]);
        }
    }
        function airdrop(address[] memory recipients, uint256 amount)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < recipients.length; i++) {
            mint(recipients[i], amount);
        }
    }


    function setPrice(uint256 price_)
        public
        onlyOwner
    {
        price = price_;
    }

    function buy() public payable whenNotPaused {
        require(msg.value > 0, "Value must be greater than 0");
        uint256 amount = msg.value / price;
        mint(msg.sender, amount);
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Balance must be greater than 0");
        payable(msg.sender).transfer(balance);
    }

    function withdrawERC20(address tokenAddress) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Balance must be greater than 0");
        token.transfer(msg.sender, balance);
    }



    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}

