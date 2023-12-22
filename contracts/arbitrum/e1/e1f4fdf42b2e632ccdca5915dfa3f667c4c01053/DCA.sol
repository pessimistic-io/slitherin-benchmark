// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20Metadata as IERC20} from "./IERC20Metadata.sol";

contract DCA {
    struct SwapParams {
        address source;
        address target;
        address receiver;
        uint256 amountToSell;
        uint8 sourceDecimals;
        uint8 targetDecimals;
    }

    address public constant PARASWAP = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    // @dev Token to sell
    address private immutable source;
    // @dev Token to buy
    address private immutable target;
    // @dev Source token decimals
    uint8 private immutable sourceDecimals;
    // @dev Target token decimals
    uint8 private immutable targetDecimals;

    // @dev The last time a swap was done
    uint256 public lastSwap;
    // @dev The amount of time between swaps
    uint256 public interval;

    // @dev The receiver of the tokens
    address private receiver;
    // @dev The amount of `source` tokens to sell
    uint256 private amountToSell;

    mapping(address => bool) private owners;

    modifier onlyOwner() {
        require(owners[msg.sender], "Sender is not an owner");
        _;
    }

    modifier afterInterval() {
        require(_canSwap(), "Trying to swap too soon");
        _;
    }

    constructor(
        address _owner,
        address _receiver,
        address _source,
        address _target,
        uint256 _interval,
        uint256 _amountToSell
    ) {
        require(_interval >= 1 hours, "Interval too small");
        require(_amountToSell > 0, "Amount to sell cannot be 0");

        owners[_owner] = true;

        receiver = _receiver;
        source = _source;
        target = _target;
        interval = _interval;
        amountToSell = _amountToSell;

        sourceDecimals = IERC20(_source).decimals();
        targetDecimals = IERC20(_target).decimals();

        IERC20(_source).approve(0x216B4B4Ba9F3e719726886d34a177484278Bfcae, type(uint256).max);
    }

    function canSwap() public view returns (bool) {
        return _canSwap();
    }

    function swapParams() public view returns (SwapParams memory) {
        return SwapParams({
            source: source,
            target: target,
            receiver: receiver,
            amountToSell: amountToSell,
            sourceDecimals: sourceDecimals,
            targetDecimals: targetDecimals
        });
    }

    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    function addOwner(address newOwner) external onlyOwner {
        owners[newOwner] = true;
    }

    function removeOwner(address ownerToRemove) external onlyOwner {
        owners[ownerToRemove] = false;
    }

    function setReceiver(address newReceiver) external onlyOwner {
        receiver = newReceiver;
    }

    function setInterval(uint256 newInterval) external onlyOwner {
        interval = newInterval;
    }

    function setAmountToSell(uint256 newAmountToSell) external onlyOwner {
        amountToSell = newAmountToSell;
    }

    function swap(bytes calldata data) external afterInterval onlyOwner {
        address receiverCache = receiver;

        uint256 initialSourceBalance = IERC20(source).balanceOf(address(this));
        uint256 initialTargetBalance = IERC20(target).balanceOf(receiverCache);

        (bool success,) = PARASWAP.call{value: 0}(data);

        require(success, "Failed to swap");
        require(
            initialSourceBalance - amountToSell == IERC20(source).balanceOf(address(this)), "Source amount mismatch"
        );
        require(initialTargetBalance < IERC20(target).balanceOf(receiverCache), "Target amount mismatch");

        lastSwap = block.timestamp;
    }

    function _canSwap() internal view returns (bool) {
        return block.timestamp >= lastSwap + interval;
    }
}

