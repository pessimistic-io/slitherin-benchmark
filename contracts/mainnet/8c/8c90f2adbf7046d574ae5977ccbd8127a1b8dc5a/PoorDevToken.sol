pragma solidity >= 0.6.12;

import "./ERC20.sol";
import "./Ownable.sol";

import "./IUniswapV2Router01.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./ICommunityFairLaunch.sol";

// .______     ______     ______   .______          _______   ___________    ____
// |   _  \   /  __  \   /  __  \  |   _  \        |       \ |   ____\   \  /   /
// |  |_)  | |  |  |  | |  |  |  | |  |_)  |       |  .--.  ||  |__   \   \/   /
// |   ___/  |  |  |  | |  |  |  | |      /        |  |  |  ||   __|   \      /
// |  |      |  `--'  | |  `--'  | |  |\  \----.   |  '--'  ||  |____   \    /
// | _|       \______/   \______/  | _| `._____|   |_______/ |_______|   \__/

// Website: https://poordev.vip
// Twitter: https://twitter.com/poordev_erc
// Telegram: https://t.me/poordev_erc
// Docs: https://docs.poordev.vip/

// Presale at our website on 8th June. Share your referral link to earn 5% bonus
// Airdrop to $BEN, $PSYOP & $LOYAL holders. Share your referral link to earn 20% bonus

contract PoorDevToken is Ownable, ERC20 {

    mapping(address => bool) public blacklists;

    uint256 public constant MAX_SUPPLY = 100000000000 ether; // 100,000,000,000 $PODEB - 100b

    constructor() ERC20("Poor Dev", "PODEB") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) override internal virtual {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}
