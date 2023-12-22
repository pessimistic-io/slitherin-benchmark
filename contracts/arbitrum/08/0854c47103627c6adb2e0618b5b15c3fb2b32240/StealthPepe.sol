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
 * @title StealthPepe
 * @author 0xFurie
 * @notice 
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
 */

contract StealthPepe is ERC20, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    address public constant ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    address public immutable deployer;

    bool public lpCreated = false;

    address public pair;
    address public immutable weth;

    constructor() ERC20("Stealth Pepe", "sPEPE") {
        weth = IUniswapV2Router02(ROUTER).WETH();
        deployer = _msgSender();
    }

    receive() external payable {}

    function createLP() external onlyOwner {
        require(!lpCreated, "LP already created");
        lpCreated = true;
        _mint(address(this), MAX_SUPPLY);
        _approve(address(this), ROUTER, MAX_SUPPLY);
        IUniswapV2Factory _factory = IUniswapV2Factory(
            IUniswapV2Router02(ROUTER).factory()
        );
        address _pair = _factory.getPair(
            address(this),
            IUniswapV2Router02(ROUTER).WETH()
        );
        if (_pair == address(0)) {
            pair = _factory.createPair(
                address(this),
                IUniswapV2Router02(ROUTER).WETH()
            );
        } else {
            pair = _pair;
        }
        IUniswapV2Router02(ROUTER).addLiquidityETH{
            value: address(this).balance
        }(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
        renounceOwnership();
    }

    function sweep() external {
        uint256 balance = address(this).balance;
        payable(deployer).transfer(balance);
    }

    function sweepERC20(address token) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(deployer, balance);
    }

}

