// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "./ERC20.sol";
import "./AggregatorV3Interface.sol";
import "./myToken.sol";
import "./console.sol";
import "./Strings.sol";

contract Dex {
    event buy(address account, address _tokenAddr, uint256 _cost, uint256 _amount);
    event sell(address account, address _tokenAddr, uint256 _cost, uint256 _amount);

    // key: deployedTokenAddress, value: tokenAddressForChainlink
    mapping(address => address) public supportedTokenAddr;

    AggregatorV3Interface public feed;

    modifier supportsToken(address _tokenAddr) {
        require(supportedTokenAddr[_tokenAddr] != address(0x0), "This token is not supported");
        _;
    }

    function setPriceFeed(address _tokenAddr) private {
        feed = AggregatorV3Interface(supportedTokenAddr[_tokenAddr]);
    }

    constructor(address[] memory _tokenAddrs, address[] memory _addrsForChainlink) {
        for(uint256 i = 0; i < _tokenAddrs.length; i++) {
            supportedTokenAddr[_tokenAddrs[i]] = _addrsForChainlink[i];
        }
    }

    function getLatestPrice() public view returns (int) {
        ( , int price, , , ) = feed.latestRoundData();
        return price;
    }

    function getPrice(address _tokenAddr) public returns (int) {
        setPriceFeed(_tokenAddr);
        return getLatestPrice();
    }


    function buyToken(address _tokenAddr, uint256 _cost) external payable supportsToken(_tokenAddr){
        ERC20 token = ERC20(_tokenAddr);

        // eth
        require(msg.value == _cost, "Insufficient fund");

        uint price = uint(getPrice(_tokenAddr));

        // _cost / price
        // uint256 amount = (_cost / price) - (_cost % price);
        // uint256 amount = (_cost / price) * 0.95;
        uint256 amount = _cost / price;

        console.log("amount:", amount);
        console.log("balance:", token.balanceOf(address(this)));

        // erc20 token
        require(token.balanceOf(address(this)) >= amount, "Token sold out");

        token.transfer(msg.sender, amount);

        emit buy(msg.sender, _tokenAddr, _cost, amount);
    }
    
    function sellToken(address _tokenAddr, uint256 _amount) external {
    // function sellToken(address _tokenAddr, uint256 _cost) external {
        ERC20 token = ERC20(_tokenAddr);
        // erc20 token
        require(token.balanceOf(msg.sender) >= _amount, "Insufficient token balance");
        // require(token.balanceOf(msg.sender) >= _cost, "Insufficient token balance");

        uint price = uint(getLatestPrice());
        // uint256 amount = _cost / price;
        uint256 cost = _amount / price;

        // require(address(this).balance >= amount, "Dex does not have enough funds");
        require(address(this).balance >= cost, "Dex does not have enough funds");

        token.transferFrom(msg.sender, address(this), cost);
        (bool success, ) = payable(msg.sender).call{value: cost}("");
        require(success, "ETH transfer failed");

        emit sell(msg.sender, _tokenAddr, cost, _amount);
    }
}

