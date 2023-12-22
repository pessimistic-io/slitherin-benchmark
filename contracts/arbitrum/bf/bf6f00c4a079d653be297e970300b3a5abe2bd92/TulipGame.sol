// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./Ownable.sol";
import "./IERC20.sol";

contract TulipGame is Ownable {

    enum ETulipGameStatus {
        NotStart,
        InjectDivinePower,
        CaressTulipBlessing
    }

    ETulipGameStatus public TulipGameStatus;

    uint256 public singleTulipPowerPrice = 0.01 ether;

    uint256 public singleTulipToken = 70_000_000 ether;
    uint256 public remainTulipPowerCopies = 10000;
    mapping(address => uint256) public injectUserInfos;

    uint256 public holyMoment = 6 * 60 * 60;

    uint256 public lastUserCaressTulipTimestamp;
    address public currentHolyMessenger;
    uint256 public currentCaressTulipPrice;
    uint256 public currentRound = 1;
    mapping(uint256 => address) public holyMessengers;
    mapping(uint256 => mapping(address => uint256)) public currentPlayerInfo;

    address public teamAddress;
    address public liquidityLock;
    address public routerAddress = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public tulipCoin;
    address public tulipGameFeeAddress;

    event eveInjectDivinePower(address account, uint256 quantity);
    event eveKissTulip(address newAccount, uint256 amount, uint256 tulipTimestamp, address lastAccount);
    event eveKissTulipWin(address account, uint256 amount, uint256 timestamp);

    constructor(address TeamAddress_, address liquidityLock_) {
        teamAddress = TeamAddress_;
        liquidityLock = liquidityLock_;
    }


    receive() payable external {}

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Must from real wallet address");
        _;
    }


    function InjectDivinePower(uint256 _quantity) payable public callerIsUser {
        require(TulipGameStatus == ETulipGameStatus.InjectDivinePower, "Not in the stage of injecting divine power.");
        require(remainTulipPowerCopies >= _quantity, "The number of divine blessings has been fully subscribed.");
        require(injectUserInfos[msg.sender] + _quantity <= 10, "Each address can inject up to 10 units of energy. Please enter the correct number.");
        require(msg.value >= _quantity * singleTulipPowerPrice, "You don't have enough Ether divine power, please practice to obtain it.");
        if (msg.value > _quantity * singleTulipPowerPrice) {
            (bool success,) = msg.sender.call{value : msg.value - _quantity * singleTulipPowerPrice}("");
            require(success, "Transfer failed.");
        }
        IERC20(tulipCoin).transfer(msg.sender, _quantity * singleTulipToken);
        remainTulipPowerCopies -= _quantity;
        emit eveInjectDivinePower(msg.sender, _quantity);
        injectUserInfos[msg.sender] += _quantity;
        if (remainTulipPowerCopies == 0) {
            TulipGameStatus = ETulipGameStatus.CaressTulipBlessing;
            currentHolyMessenger = teamAddress;
            currentCaressTulipPrice = singleTulipToken;
            lastUserCaressTulipTimestamp = block.timestamp;
            (bool openTransferSuccess,) = address(tulipCoin).call(abi.encodeWithSignature("openTransfer()"));
            require(openTransferSuccess, "openTransfer failed");
            uint256 amountTokenDesired = 250_000_000_000 ether;
            uint256 poolReward = 40 ether;
            IERC20(tulipCoin).approve(address(routerAddress), amountTokenDesired);
            (bool success,) = payable(address(routerAddress)).call{value : poolReward}(
                abi.encodeWithSignature("addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                tulipCoin, amountTokenDesired, amountTokenDesired, poolReward, liquidityLock, block.timestamp)
            );
            require(success, "addLiquidityETHCaller failed");
        }
    }

    function KissTulip() payable public callerIsUser {
        if (block.timestamp > lastUserCaressTulipTimestamp + holyMoment) {
            require(TulipGameStatus == ETulipGameStatus.CaressTulipBlessing, "Not in the stage of caressing Tulip blessing.");
            uint256 totalbalance = address(this).balance;
            uint256 rewardBalance = totalbalance * 80 / 100;
            (bool success,) = currentHolyMessenger.call{value : rewardBalance}("");
            require(success, "Failed to obtain divine envoy reward.");
            holyMessengers[currentRound] = currentHolyMessenger;
            currentRound++;
            currentHolyMessenger = teamAddress;
            currentCaressTulipPrice = singleTulipToken;
            lastUserCaressTulipTimestamp = block.timestamp;
            emit eveKissTulipWin(msg.sender, rewardBalance, block.timestamp);
        } else {
            require(TulipGameStatus == ETulipGameStatus.CaressTulipBlessing, "Not in the stage of caressing Tulip blessing.");
            require(IERC20(tulipCoin).balanceOf(msg.sender) >= currentCaressTulipPrice, "You don't have enough $TLIP, please buy it by DEX.");
            require(currentPlayerInfo[currentRound][msg.sender] <= 10, "In this round, you can kiss tulips up to 10 times at most. Please switch accounts.");
            uint256 lastCaressTulipPrice = currentCaressTulipPrice - singleTulipToken;
            uint256 holyCashback = singleTulipToken * 25 / 100;
            uint256 teamCashBack = singleTulipToken * 15 / 100;
            uint256 poolCashBack = singleTulipToken * 50 / 100;
            uint256 deathBurnBack = singleTulipToken * 10 / 100;
            emit eveKissTulip(msg.sender, currentCaressTulipPrice, block.timestamp, currentHolyMessenger);
            IERC20(tulipCoin).transferFrom(msg.sender, address(this), currentCaressTulipPrice);
            IERC20(tulipCoin).transfer(currentHolyMessenger, lastCaressTulipPrice + holyCashback);
            IERC20(tulipCoin).transfer(teamAddress, teamCashBack);
            IERC20(tulipCoin).transfer(tulipGameFeeAddress, poolCashBack);
            IERC20(tulipCoin).transfer(address(0x000000000000000000000000000000000000dEaD), deathBurnBack);
            currentHolyMessenger = msg.sender;
            currentCaressTulipPrice += singleTulipToken;
            lastUserCaressTulipTimestamp = block.timestamp;
            currentPlayerInfo[currentRound][msg.sender]++;
        }

    }


    function StartTulipGame() external onlyOwner {
        require(TulipGameStatus == ETulipGameStatus.NotStart, "Not in the stage of NotStart.");
        TulipGameStatus = ETulipGameStatus.InjectDivinePower;
    }

    function SetTulipCoin(address tulipCoin_) external onlyOwner {
        tulipCoin = tulipCoin_;
    }

    function SetTulipGameFeeAddress(address tulipGameFeeAddress_) external onlyOwner {
        tulipGameFeeAddress = tulipGameFeeAddress_;
    }

}

