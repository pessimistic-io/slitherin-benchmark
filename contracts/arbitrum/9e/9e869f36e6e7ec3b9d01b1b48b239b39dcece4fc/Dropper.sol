// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";

import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./SafeERC20.sol";

/**
 * @title Pepe Dropper
 * @author 0xFurie
 * @notice READ BELOW!
 * 
 ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣠⡤⢤⣤⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡴⠞⠉⠁⠀⠀⠀⠀⠀⠀⠀⠉⠙⠲⢤⡀⠀⠀⣠⡴⠒⠋⠉⠉⠉⠉⠉⠛⠲⢤⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢶⡋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠳⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⡞⠁⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⣀⣀⣀⡀⠀⠀⠀⢻⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠏⠀⠀⠀⠀⠀⣀⣤⠶⠚⠉⠁⠀⠀⠀⠀⠀⠀⠉⠙⠲⢤⣀⣻⣀⣀⣀⣀⣤⣤⠤⠤⠤⠤⠤⣤⣄⣀⣹⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⠀⠀⠀⠀⠀⠘⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⣍⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠓⢤⡀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡤⠤⠶⠒⠒⠒⠒⠒⠒⠚⠻⠦⣄⠀⠀⣀⣠⠤⠶⠖⠒⠒⠒⢚⣛⣓⠶⠤⠽⣦⣀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣾⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡤⠶⠛⠉⢀⣀⣠⠤⠶⠖⠒⠛⠛⠛⠓⠶⠤⣼⣟⣫⡥⠶⠖⠛⠉⠉⠉⠉⠉⠉⠉⠉⠛⠳⠶⣽⣧⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠉⢰⡇⠀⠀⠀⠀⠀⠀⠀⣀⣴⣶⣯⡥⠶⠒⠛⠉⠁⠀⠀⠀⠀⠀⣀⣀⣤⣤⡤⠤⠤⠭⢿⠁⠀⠀⣀⣤⡤⠶⠒⠒⢺⣯⣭⣉⠙⠓⠒⠦⣽⣷⡄
⠀⠀⠀⠀⠀⠀⠀⡼⠃⠀⠀⢸⣧⠀⠀⠀⠀⠀⠀⠈⣯⡍⠁⠀⠀⢀⣀⣀⣀⣠⠤⠴⢒⣿⠿⣿⣾⣿⣦⣄⠀⠀⠀⢘⡗⠚⠉⠁⠀⠀⢀⣴⣟⠙⣿⣿⣿⣿⣦⠀⠀⠀⠹⡄
⠀⠀⠀⠀⠀⠀⣸⠃⠀⠀⠀⠙⠉⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠛⡿⣍⡉⠀⠀⠀⠀⣰⣿⣿⣦⣾⡿⠛⢿⣿⣧⠀⢀⣼⠁⠀⠀⠀⠀⢀⣿⣿⡿⣿⣿⡁⢈⣿⣿⡆⣀⣠⡼⠀
⠀⠀⠀⠀⠀⣰⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⢧⣀⡉⠲⠦⣀⡀⣿⣿⣿⣯⣿⣷⣶⣾⡿⠿⠓⢋⡽⠓⠶⠦⢤⣀⣼⠿⠿⠿⠿⠿⠿⠟⠛⠛⢉⣿⠟⠀⠀
⠀⠀⠀⠀⣰⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠙⠒⠲⠯⠿⠯⣯⣯⣭⣭⣤⢤⣦⠶⠖⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀
⠀⠀⠀⣰⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣤⠾⠛⠀⠀⠀⠀⠰⣦⣀⠀⠀⠀⠀⠀⠀⢀⣀⣤⠶⠋⠀⠀⠀⠀⠀⠀
⠀⠀⣰⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡤⠶⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⣿⠛⠉⠉⠉⠁⠙⢦⡀⠀⠀⠀⠀⠀⠀
⠀⣰⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠹⡄⠀⠀⠀⠀⠀
⢰⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⡄⠀⠀⠀⠀
⣼⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣷⠀⠀⠀⠀
⢻⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠞⠋⠉⠉⠉⠉⠙⠛⠒⠲⠶⠦⣤⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣠⠴⠞⠙⣧⠀⠀⠀
⠸⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡟⠀⠀⣤⠤⠤⠤⠤⠤⠤⠤⣄⣀⣀⠀⠀⠈⠉⠉⠛⠒⠒⠒⠲⠶⠶⠶⠶⠶⠶⠒⠒⠚⠋⠉⠁⠀⠀⢀⣴⠟⠀⠀⠀
⠀⠹⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡀⠀⠀⣷⡀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠙⠓⠒⠶⠦⠤⠤⣤⣤⣀⣤⣀⣀⣀⣀⣀⣠⣤⠤⠤⠤⠤⠖⠒⡟⠁⠀⠀⠀⠀
⠀⠀⠹⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢷⡀⠀⠈⠛⠙⠛⠛⠓⠒⠶⠶⠦⠤⣤⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠇⠀⠀⠀⠀⠀
⠀⠀⠀⠈⠳⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⢦⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠉⠛⠒⠒⠒⠒⠒⠒⠶⠦⠤⠶⠶⠶⢶⡶⠤⠖⠚⠉⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠈⠓⠦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠴⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠶⠤⣄⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡤⠖⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠓⠒⠶⠶⠦⠤⣤⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⡤⠴⠶⠖⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
the ultimate meme coin that combines the fun of Pepe the Frog with the thrill of stealth! With a max supply of 1 billion tokens, 
no buy or sell taxes, and a fully transparent approach, our team doesn't hold any funds, ensuring fair distribution for everyone.

Stealth Pepe is a game-changer in the meme coin world, offering a unique, completely stealth experience. 
The only hint to our existence is a discreet Telegram link tucked away in the code comments. 
Join our ever-growing community and let's take Stealth Pepe to the moon, all while sharing our love for the iconic Pepe the Frog!⠀


Renouncing ownership and liquidity locked forever.

https://t.me/stealthpepe

*/

contract Dropper is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    constructor() {}
    function drop(IERC20 _token, address[] memory addresses, uint256 qty) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            _token.safeTransferFrom(msg.sender, addresses[i], qty);
        }
    }
}

