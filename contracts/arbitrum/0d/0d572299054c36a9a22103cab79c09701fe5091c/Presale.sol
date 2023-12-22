// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IERC20.sol";
import "./SafeERC20.sol";

contract Presale {

    using SafeERC20 for IERC20;

    IERC20 public immutable volta;
    IERC20 public immutable token;
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    uint256 public immutable unlockTime;
    address public immutable treasury;
    uint256 public immutable price;
    uint256 public saleAmount;

    mapping(address buyer => uint256 lockedTokenAmount) public locked;

    /**
     * @param _volta volta token, 18 decimals
     * @param _token token used to purchase volta
     * @param _startTime presale start timestamp
     * @param _endTime presale end timestamp
     * @param _treasury address that receives presale funds
     * @param _price price per volta in _token amount
     * @param _saleAmount amount of volta tokens to be sold
     */
    constructor(IERC20 _volta, IERC20 _token, uint256 _startTime, uint256 _endTime, address _treasury, uint256 _price, uint256 _saleAmount) {
        require(address(_volta) != address(0)
            && address(_token) != address(0)
            && _startTime >= block.timestamp
            && _endTime > _startTime
            && _treasury != address(0)
            && _price != 0
            && _saleAmount != 0,
            "ConstructorParams"
        );
        volta = _volta;
        token = _token;
        startTime = _startTime;
        endTime = _endTime;
        treasury = _treasury;
        price = _price;
        unlockTime = endTime + 2 weeks;
        saleAmount = _saleAmount;
    }

    /**
     * @notice Function to purchase volta tokens
     * @param _spendAmount amount of tokens to spend to buy volta
     */
    function purchase(uint256 _spendAmount) external {
        // Must be within presale time limits
        require(block.timestamp >= startTime, "Presale not started");
        require(block.timestamp < endTime, "Presale ended");
        // Require the buyer to have enough purchase tokens
        require(token.balanceOf(msg.sender) >= _spendAmount, "Insufficient balance");
        // Transfer the proceeds to treasury
        token.safeTransferFrom(msg.sender, treasury, _spendAmount);
        // Calculate the volta amount
        uint256 _voltaAmount = _spendAmount * 1e18 / price;
        // Require the contract to have enough volta tokens to sell
        require(saleAmount >= _voltaAmount, "Insufficient VOLTA balance");
        saleAmount -= _voltaAmount;
        // Allocate the volta to the buyer
        locked[msg.sender] += _voltaAmount;
    }

    /**
     * @notice Claim tokens bought from presale after lock period
     */
    function claim() external {
        // Claiming must be done after unlock time
        require(block.timestamp >= unlockTime, "Locked");
        // Get allocation amount
        uint256 _amount = locked[msg.sender];
        // Clear allocation from buyer
        delete locked[msg.sender];
        // Transfer allocation to buyer
        volta.safeTransfer(msg.sender, _amount);
    }

    function recover() external {
        require(block.timestamp > endTime, "Presale not ended");
        // saleAmount is leftover tokens
        volta.safeTransfer(treasury, saleAmount);
    }
}

