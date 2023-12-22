// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./ERC20.sol";
import "./ITradeToken.sol";

contract TradeToken is ERC20, ITradeToken {
    constructor(address _manager, uint256 _decimals, string memory _name, string memory _symbol)ERC20(_manager){
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    modifier _onlyInviteManager(){
        require(IManager(manager).inviteManager() == msg.sender, 'TradeToken: only minter');
        _;
    }

    function mint(address _account, uint256 _amount) external override _onlyInviteManager {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        require(msg.sender == _account, "TradeToken: only burn by self");
        _burn(_account, _amount);
    }
}


