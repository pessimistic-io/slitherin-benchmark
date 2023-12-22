// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IUniswapV2Pair.sol";


contract DragonFarm is ERC20Upgradeable, OwnableUpgradeable {

    IUniswapV2Pair public pair;

    uint256 public constant MAX_SUPPLY = 10e24;

    bool public tradingOpen;

    event CheaterBlocked(address who);
    event TradingOpen();
    event AuthorizedAddress(address who);
    event Burned(address who, uint256 amount);
    event Minted(address who, uint256 amount);
    event SuperMinterAdded(address who);
    event SuperBurnerAdded(address who);

    error TradingClosed();

    mapping(address => bool) public catched;
    mapping(address => bool) public minter;
    mapping(address => bool) public burner;
    mapping(address => bool) public authorized;
    
    function initialize (
        address genesisWallet,
        uint256 alloc
        ) public initializer {
        __ERC20_init("Dragon Farm", "DRG");
        __Ownable_init();
        
        authorizeWallet(genesisWallet);
        authorizeWallet(address(0));
        _mint(genesisWallet, alloc);
    }

    function mint (address to, uint256 amount) external {
        require(totalSupply() + amount <= MAX_SUPPLY);
        require(minter[_msgSender()]);
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function burn (address from, uint256 amount) external {
        require(burner[_msgSender()]);
        _burn(from, amount);
        emit Burned(from, amount);
    }

    function _beforeTokenTransfer (
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(!catched[from] && !catched[to], "ERROR : cheater blocked");
        if (!tradingOpen) { 
            if (!authorized[from]) {
                if (to == address(pair))  {
                    blockCheater(from);
                    emit CheaterBlocked(from);
                }
                else {
                    revert TradingClosed();
                }
            }
        }
    }

    function addSuperMinter(address who) external onlyOwner {
        minter[who] = true;
        emit SuperMinterAdded(who);
    }

    function addSuperBurner(address who) external onlyOwner {
        burner[who] = true;
        emit SuperBurnerAdded(who);
    }

    function setPairAddress(address _pair) external onlyOwner {
        require(_pair != address(0));
        pair = IUniswapV2Pair(_pair);
    }

    function openTrading() external onlyOwner {
        tradingOpen = true;
        emit TradingOpen();
    }

    function authorizeWallet(address who) public onlyOwner {
        authorized[who] = true;
        emit AuthorizedAddress(who);
    }

    function blockCheater (address who) internal {
        catched[who] = true;
        emit CheaterBlocked(who);
    }

}
