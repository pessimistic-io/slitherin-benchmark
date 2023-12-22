// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";
import "./KEI.sol";
import "./ReserveController.sol";
import "./YieldHandlerRegistry.sol";
import "./USDCHandler.sol";
import "./DAIHandler.sol";

contract KEIManager is Owned {

    ReserveController public reserveController;
    YieldHandlerRegistry public registry;

    USDCHandler public usdcHandler;
    DAIHandler public daiHandler;
    KEI private KEIToken;

    address[] public supportedStablecoins;
    mapping(address => bool) public whitelistedStablecoins;
    mapping(address => uint256) public stablecoinReserves;

    bool public contractPaused;    
    uint256 public totalUserDeposits;
    address public KEIAddress;

    mapping(address => uint256) public deployedTokens;

    constructor (address _owner, address _KEIAddress) Owned(_owner) {
        KEIAddress = _KEIAddress;
        KEIToken = KEI(_KEIAddress);
        contractPaused = false;
    }

    function depositAndMint(address _token, uint256 _amount) public {
        require(isWhitelisted(_token) == true, "Stablecoin not supported.");
        require(_amount > 0, "Amount must be greater than 0");
        require(contractPaused == false, "Protocol paused");
        //require(reserveController.canDepositStablecoin(_token, _amount) == true, "Can't deposit");

        ERC20(_token).transferFrom(msg.sender, address(this), _amount);

        if (reserveController.isPenaltyEnabled()) {
            uint256 penaltyFee = reserveController.calculatePenalty(_token, _amount);
            uint256 mintAmount = _amount * (10000 - penaltyFee) / 10000;

            KEIToken.mint(msg.sender, mintAmount);
            addReserves(_token, mintAmount);

        } else {
            KEIToken.mint(msg.sender, _amount);
            addReserves(_token, _amount);
        }
    }

    /*function burnAndRedeem(uint256 _amount, address _token) public {
        require(reserveController.redemptionsAllowed() == true, "Redemptions disabled");
        require(_token == address(KEIToken), "You cant redeem that token");

        KEIToken.burn(msg.sender, _amount);

        uint256 arrayLength = supportedStablecoins.length;
        uint256[] memory redemptionAmounts = new uint256[](arrayLength);

        redemptionAmounts = reserveController.calculateRedemtion(_amount, _token);

        for (uint i = 0; i < supportedStablecoins.length; i++) {
            ERC20(supportedStablecoins[i]).transfer(msg.sender, redemptionAmounts[i]);
            removeReserves(supportedStablecoins[i], redemptionAmounts[i]);
        }
    }*/

    function depositReserves(address stablecoin, uint256 amount) external {
        address handlerAddress = registry.getYieldHandler(stablecoin);
        require(handlerAddress != address(0), "Handler not found");
        require(ERC20(stablecoin).approve(handlerAddress, amount), "Approve failed");

        IYieldHandler handler = IYieldHandler(handlerAddress);
        handler.deposit(address(this), amount);
    }

    function calculateAccruedYield() public returns(uint256) {
        uint256 totalReserves = getTotalReserves();
        
        // Yield accrued is the difference between the total amount of reserves
        // in the protocol (Each handler and KEIManager contract) and total user deposits.
        uint256 yield = totalReserves - totalUserDeposits;

        return yield;
    }

    function getTotalReserves() public returns(uint256) {
        uint256 totalReserves = 0;
        
        for (uint256 i=0; i < supportedStablecoins.length; i++) {
            address handlerAddress = registry.getYieldHandler(supportedStablecoins[i]);
            IYieldHandler handler = IYieldHandler(handlerAddress);

            totalReserves += handler.getBalance(address(this));
        }

        for (uint256 i=0; i < supportedStablecoins.length; i++) {
            totalReserves += ERC20(supportedStablecoins[i]).balanceOf(address(this));
        }

        return totalReserves;
    }

    function addReserves(address _stablecoin, uint256 _amount) public {
        stablecoinReserves[_stablecoin] += _amount;
        totalUserDeposits += _amount;
    }

    function removeReserves(address _stablecoin, uint256 _amount) public {
        stablecoinReserves[_stablecoin] -= _amount;
        totalUserDeposits -= _amount;
    }

    function addStablecoin(address _token) public {
        whitelistedStablecoins[_token] = true;
        supportedStablecoins.push(_token);
    }

    function removeStablecoin(uint256 index) public {
        // Check if the index is within the array bounds
        require(index < supportedStablecoins.length, "Index out of bounds");

        // If the index is the last element in the array, remove it directly
        if (index == supportedStablecoins.length - 1) {
            supportedStablecoins.pop();
            whitelistedStablecoins[supportedStablecoins[index]] = false;
        } else {
            // Replace the stablecoin at the specified index with the last stablecoin in the array
            supportedStablecoins[index] = supportedStablecoins[supportedStablecoins.length - 1];

            // Remove the last stablecoin from the array
            supportedStablecoins.pop();
            whitelistedStablecoins[supportedStablecoins[index]] = false;
        }
    }

    function isWhitelisted(address _token) public view returns(bool) {
        if (whitelistedStablecoins[_token] == true) {
            return true;
        }

        return false;
    }

    function setRegistry(address _contract) public {
        registry = YieldHandlerRegistry(_contract);
    }

    function setReserveController(address _contract) public onlyOwner() {
        reserveController = ReserveController(_contract);
    }

    function pauseContract(bool _paused) public onlyOwner() {
        contractPaused = _paused;
    }

    function getStablecoinReserve(address _stablecoin) public view returns(uint256) {
        return stablecoinReserves[_stablecoin];
    }

    function getTotalUserDeposits() public view returns(uint256) {
        return totalUserDeposits;
    }

    function getSupportedStablecoins() public view returns(address[] memory) {
        return supportedStablecoins;
    }
}

