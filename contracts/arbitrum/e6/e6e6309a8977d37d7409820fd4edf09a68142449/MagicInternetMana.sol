/*

███╗░░░███╗██╗███╗░░░███╗░█████╗░███╗░░██╗░█████╗░
████╗░████║██║████╗░████║██╔══██╗████╗░██║██╔══██╗
██╔████╔██║██║██╔████╔██║███████║██╔██╗██║███████║
██║╚██╔╝██║██║██║╚██╔╝██║██╔══██║██║╚████║██╔══██║
██║░╚═╝░██║██║██║░╚═╝░██║██║░░██║██║░╚███║██║░░██║
╚═╝░░░░░╚═╝╚═╝╚═╝░░░░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝░░╚═╝

  
                               ▄▄▄▄,_
                           _▄████▀└████▄,
                       ▄███████▌   _▄█████▄_
                      ╓████████▄██▄╟██████████▄
                     ╓█████▀▀█████████████⌐ ╓████▄_
                     ╟███`     ╟███████████████████
                      ██▌     ▐████╙▀▐████████▀╙"╙▀" ,▄▄,
                     ,█▀       ,██▄▄ ▄▄█████w     ╒████████▄▄▄▄▄▄▄▄▄,,__
                              ª▀▀▀▀▀▀▀▀"" _,▄▄_▄▄█████████████████████▀▀
                            ╒██▄▄▄▄▄▄███████████████████████████▀▀╙"
                            ▐███████████████████▀▀▀▀▀╙╙"─
                         ▄██████████▀▀▀╙"`
                     ,▄███████▀""
                  ▄███████▀"                               _▄▄█▀▀████▄▄_
              ,▄████████▀                _,▄▄▄,_        ,███▀╓█▄   ╙█████▄
            ▄████████▀"             _▄█▀▀""╙▀██████▄ ╓█████▌ ╙▀"███L╙█████▌
             """╙"─               ▄███▐██▌╓██▄╙████████████▌ ╚█_`▀▀  ████▀
                              _▄█████" └█▄╙██▀ ╫████████████┐  ╙    '"─
                            '▀███████▌  "█─    ▐▀▀"  └"╙▀▀▀╙"         ▄▄_
                                 ╙▀▀██▌                           ,▄█████
                         ,▄▄▄▄▄▄▄▄,______              ___,▄▄▄█████████▀"
                        ██████████████████████████████████████████████▄
                        ╙██████████████████████████████████████████████
                            '╙▀▀█████████████████████████████████▀▀▀╙─
                                     `""╙"╙╙""╙╙╙╙""╙╙"""─`


█▀▄▀█ ▄▀█ █▀▀ █ █▀▀   █ █▄░█ ▀█▀ █▀▀ █▀█ █▄░█ █▀▀ ▀█▀   █▀▄▀█ ▄▀█ █▄░█ ▄▀█
█░▀░█ █▀█ █▄█ █ █▄▄   █ █░▀█ ░█░ ██▄ █▀▄ █░▀█ ██▄ ░█░   █░▀░█ █▀█ █░▀█ █▀█

*/ // SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "./ERC20.sol";

interface IFrenRewarder {
    function fill(uint256 day, uint256 amount) external;
    function setBased(address) external;
}

contract MagicInternetMana is ERC20 {
    address public admin;

    uint256 public constant maxSupply = 108_000_000e18;

    address public frenRewarder;
    uint256 public startTimestamp;
    mapping(uint256 => bool) public isRewardMinted;

    event FillFrensRewarder(address sender, uint256 day, uint256 amount);

    constructor(address admin_) ERC20("Magic Internet Mana", "miMana") {
        admin = admin_;

        _mint(admin, 72_000_000e18);
    }

    function initialize(address frenRewarder_, uint256 startTimestamp_) external {
        require(msg.sender == admin, "ONLY ADMIN");
        require(frenRewarder_ != address(0) && startTimestamp_ > block.timestamp, "BAD PARAMS");

        frenRewarder = frenRewarder_;
        startTimestamp = startTimestamp_;

        _approve(address(this), frenRewarder, maxSupply - totalSupply());

        admin = address(0);
    }

    function getFrenRewardAmount(uint256 day) public view returns (uint256) {
        if (day < 21) return 963963963963963000000;
        if (day < 21 * 2) return 639639639639630000000;
        if (day < 21 * 3) return 396396396396300000000;
        if (day < 21 * 4) return 963963963963963000000;
        if (maxSupply - totalSupply() < 96396396396396300000000) return maxSupply - totalSupply();
        return 0;
    }

    function fillFrenRewarder(uint256 day) external {
        require(block.timestamp >= startTimestamp, "NOT STARTED");
        require(startTimestamp + day * 1 days < block.timestamp, "NOT REACHED DAY");

        if (!isRewardMinted[day]) {
            isRewardMinted[day] = true;

            uint256 amount = getFrenRewardAmount(day);
            if (amount > 0) {
                _mint(admin, amount);
            }
        }
    }
}

