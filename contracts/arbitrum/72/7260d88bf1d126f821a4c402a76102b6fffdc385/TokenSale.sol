// SPDX-License-Identifier: MIT

// https://twitter.com/dealmpoker1
// https://discord.gg/hdgaZUqBSs
// https://t.me/+OZenwkiHEpliOGY0
// https://www.facebook.com/dealmpoker

pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./Initializable.sol";
import "./TokenSaleStorage.sol";

contract TokenSale is Initializable, OwnableUpgradeable, TokenSaleStorage {
    modifier onlyController() {
        require(controller[msg.sender] == true, "Caller is not controller");
        _;
    }

    function buy(uint256 amount) public {
        require(amount >= minimumBuyAmount, "Buy amount too low");
        require(amount <= maximumBuyAmount, "Buy amount too high");

        IERC20(firstToken).transferFrom(msg.sender, buyTokenReceiver, amount);

        IERC20(secondToken).transfer(msg.sender, amount * price * 1e12);

        emit BuyEvent(
            msg.sender,
            buyTokenReceiver,
            amount,
            firstToken,
            amount * price,
            secondToken,
            block.timestamp
        );
    }

    function deposit() public {
        IERC20(secondToken).transferFrom(
            msg.sender,
            depositReceiver,
            depositAmount
        );

        emit DepositEvent(
            msg.sender,
            depositAmount,
            secondToken,
            depositReceiver
        );
    }

    function getPrice() external view override returns (uint256) {
        return price;
    }

    function claim(
        address _tokenAddress,
        uint256 _amount
    ) public onlyController {
        IERC20(_tokenAddress).transfer(msg.sender, _amount);
    }

    function setPrice(uint256 _newPrice) public onlyController {
        price = _newPrice;
    }

    function setMinimumBuyAmount(
        uint256 _newMinimumBuyAmount
    ) public onlyController {
        minimumBuyAmount = _newMinimumBuyAmount;
    }

    function setMaximumBuyAmount(
        uint256 _newMaximumBuyAmount
    ) public onlyController {
        maximumBuyAmount = _newMaximumBuyAmount;
    }

    function setDepositAmount(uint256 _newDepositAmount) public onlyController {
        depositAmount = _newDepositAmount;
    }

    function setFirstToken(address _newTokenAddress) public onlyController {
        firstToken = _newTokenAddress;
    }

    function setSecondToken(address _newTokenAddress) public onlyController {
        secondToken = _newTokenAddress;
    }

    function setDepositReceiver(
        address _newDepositReceiver
    ) public onlyController {
        depositReceiver = _newDepositReceiver;
    }

    function setBuyTokenReceiver(
        address _newBuyTokenReceiver
    ) public onlyController {
        buyTokenReceiver = _newBuyTokenReceiver;
    }

    function setController(
        address _addr,
        bool _value
    ) external virtual onlyOwner {
        controller[_addr] = _value;
    }
}

