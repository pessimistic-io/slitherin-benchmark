pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract ArbiTenTokenRedeem is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable preArbiTen;

    address public immutable ArbiTenAddress;

    uint public startTime;

    event ArbiTenSwap(address sender, uint amountIn, uint amountOut);
    event StartTimeChanged(uint newStartTime);
    event ArbiTenRecovery(address recipient, uint recoveryAmount);

    constructor(uint _startTime, address _preArbiTen, address _ArbiTenAddress) {
        //require(block.timestamp < _startTime, "cannot set start block in the past!");
        require(_preArbiTen != _ArbiTenAddress, "preArbiTen cannot be equal to ArbiTen");
        require(_ArbiTenAddress != address(0), "_ArbiTenAddress cannot be the zero address");
        require(_preArbiTen != address(0), "_preArbiTenAddress cannot be the zero address");

        startTime = _startTime;

        preArbiTen = _preArbiTen;
        ArbiTenAddress = _ArbiTenAddress;
    }

    function swappreArbiTenForArbiTen(uint ArbiTenSwapAmount) external nonReentrant {
        require(block.timestamp >= startTime, "token redemption hasn't started yet, good things come to those that wait");

        uint pArbiTenDecimals = ERC20(preArbiTen).decimals();
        uint ArbiTenDecimals = ERC20(ArbiTenAddress).decimals();

        uint ArbiTenSwapAmountWei = pArbiTenDecimals > ArbiTenDecimals ?
                                        ArbiTenSwapAmount / (10 ** (pArbiTenDecimals - ArbiTenDecimals)) :
                                            pArbiTenDecimals < ArbiTenDecimals ?
                                                ArbiTenSwapAmount * (10 ** (ArbiTenDecimals - pArbiTenDecimals)) :
                                                ArbiTenSwapAmount;

        require(IERC20(ArbiTenAddress).balanceOf(address(this)) >= ArbiTenSwapAmountWei, "Not enough tokens in contract for swap");

        ERC20(preArbiTen).safeTransferFrom(msg.sender, BURN_ADDRESS, ArbiTenSwapAmount);
        ERC20(ArbiTenAddress).safeTransfer(msg.sender, ArbiTenSwapAmountWei);

        emit ArbiTenSwap(msg.sender, ArbiTenSwapAmount, ArbiTenSwapAmountWei);
    }

    function setStartTime(uint _newStartTime) external onlyOwner {
        require(block.timestamp < startTime, "cannot change start block if sale has already commenced");
        require(block.timestamp < _newStartTime, "cannot set start block in the past");
        startTime = _newStartTime;

        emit StartTimeChanged(_newStartTime);
    }

    // Recover ArbiTen in case of error, only owner can use.
    function recoverArbiTen(address recipient, uint recoveryAmount) external onlyOwner {
        if (recoveryAmount > 0)
            ERC20(ArbiTenAddress).safeTransfer(recipient, recoveryAmount);
        
        emit ArbiTenRecovery(recipient, recoveryAmount);
    }
}
