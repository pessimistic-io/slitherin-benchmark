pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract _10SHARETokenRedeem is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable pre10SHARE;

    address public immutable _10SHAREAddress;

    uint public startTime;

    event _10SHARESwap(address sender, uint amountIn, uint amountOut);
    event StartTimeChanged(uint newStartTime);
    event _10SHARERecovery(address recipient, uint recoveryAmount);

    constructor(uint _startTime, address _pre10SHARE, address __10SHAREAddress) {
        //require(block.timestamp < _startTime, "cannot set start block in the past!");
        require(_pre10SHARE != __10SHAREAddress, "pre10SHARE cannot be equal to _10SHARE");
        require(__10SHAREAddress != address(0), "__10SHAREAddress cannot be the zero address");
        require(_pre10SHARE != address(0), "_pre10SHAREAddress cannot be the zero address");

        startTime = _startTime;

        pre10SHARE = _pre10SHARE;
        _10SHAREAddress = __10SHAREAddress;
    }

    function swappre10SHAREFor10SHARE(uint _10SHARESwapAmount) external nonReentrant {
        require(block.timestamp >= startTime, "token redemption hasn't started yet, good things come to those that wait");

        uint p10SHAREDecimals = ERC20(pre10SHARE).decimals();
        uint _10SHAREDecimals = ERC20(_10SHAREAddress).decimals();

        uint _10SHARESwapAmountWei = p10SHAREDecimals > _10SHAREDecimals ?
                                        _10SHARESwapAmount / (10 ** (p10SHAREDecimals - _10SHAREDecimals)) :
                                            p10SHAREDecimals < _10SHAREDecimals ?
                                                _10SHARESwapAmount * (10 ** (_10SHAREDecimals - p10SHAREDecimals)) :
                                                _10SHARESwapAmount;

        require(IERC20(_10SHAREAddress).balanceOf(address(this)) >= _10SHARESwapAmountWei, "Not enough tokens in contract for swap");

        ERC20(pre10SHARE).safeTransferFrom(msg.sender, BURN_ADDRESS, _10SHARESwapAmount);
        ERC20(_10SHAREAddress).safeTransfer(msg.sender, _10SHARESwapAmountWei);

        emit _10SHARESwap(msg.sender, _10SHARESwapAmount, _10SHARESwapAmountWei);
    }

    function setStartTime(uint _newStartTime) external onlyOwner {
        require(block.timestamp < startTime, "cannot change start block if sale has already commenced");
        require(block.timestamp < _newStartTime, "cannot set start block in the past");
        startTime = _newStartTime;

        emit StartTimeChanged(_newStartTime);
    }

    // Recover _10SHARE in case of error, only owner can use.
    function recover10SHARE(address recipient, uint recoveryAmount) external onlyOwner {
        if (recoveryAmount > 0)
            ERC20(_10SHAREAddress).safeTransfer(recipient, recoveryAmount);
        
        emit _10SHARERecovery(recipient, recoveryAmount);
    }
}
