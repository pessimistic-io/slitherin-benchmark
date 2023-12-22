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
    address public immutable treasury;
    uint256 public immutable price;

    /**
     * @param _volta volta token, 18 decimals
     * @param _token token used to purchase volta
     * @param _startTime presale start timestamp
     * @param _endTime presale end timestamp
     * @param _treasury address that receives presale funds
     * @param _price price per volta in _token amount
     */
    constructor(IERC20 _volta, IERC20 _token, uint256 _startTime, uint256 _endTime, address _treasury, uint256 _price) {
        require(address(_volta) != address(0)
            && address(_token) != address(0)
            && _startTime >= block.timestamp
            && _endTime > _startTime
            && _treasury != address(0)
            && _price != 0,
            "ConstructorParams"
        );
        volta = _volta;
        token = _token;
        startTime = _startTime;
        endTime = _endTime;
        treasury = _treasury;
        price = _price;
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
        // Require the contract to have enough volta tokens
        require(volta.balanceOf(address(this)) >= _voltaAmount, "Insufficient VOLTA balance");
        // Transfer the volta to the buyer
        volta.safeTransfer(msg.sender, _voltaAmount);
    }
}

