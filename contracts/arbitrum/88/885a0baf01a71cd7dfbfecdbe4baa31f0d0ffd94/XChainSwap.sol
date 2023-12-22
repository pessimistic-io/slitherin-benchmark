pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract XChainSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public immutable depositToken;

    uint256 public endTime;

    mapping(address => uint256) public deposited;

    address[] public depositorsArray;

    uint256 public totaldeposited;

    event Swap(address depositor, uint256 depositAmount);
    event Recovery(address tokenAddress, address recipient, uint256 tokenAmount);

    constructor(uint256 _endTime, address _depositToken) {
        require(block.timestamp < _endTime, "cannot set start block in the past!");
        require(_depositToken != address(0), "depositToken != 0");

        endTime = _endTime;
        depositToken = _depositToken;
    }

    function swapToken(uint256 tokenAmount) external nonReentrant {
        require(block.timestamp <= endTime, "token depositing is over!");
        require(tokenAmount > 0, "cannot deposit 0 wei");

        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        if (deposited[msg.sender] == 0)
            depositorsArray.push(msg.sender);

        deposited[msg.sender]+= tokenAmount;

        totaldeposited+= tokenAmount;

        emit Swap(msg.sender, tokenAmount);
    }

    // Recover tokens, only owner can use.
    function recoverTokens(address tokenAddress, address recipient, uint256 recoveryAmount) external onlyOwner {
        if (recoveryAmount > 0)
            ERC20(tokenAddress).safeTransfer(recipient, recoveryAmount);
        
        emit Recovery(tokenAddress, recipient, recoveryAmount);
    }
}
